"""
Markdown to DOCX Converter Utility.

Converts Markdown files containing Mermaid diagrams into formatted Word documents.
Handles diagram rendering, image layout calculation, and formatting normalization.
"""

import base64
import json
import logging
import re
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import List, Optional, Tuple, Union

import pypandoc
import requests
from PIL import Image

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class MarkdownToDocxConverter:
    """Handles the conversion of Markdown (with Mermaid diagrams) to DOCX."""

    # Constants for configuration
    DEFAULT_MERMAID_BASE_URL = "https://mermaid.ink/img"
    DEFAULT_REQUEST_TIMEOUT = 30
    
    # A4 Paper dimensions reference (approximate printable area at 96 DPI)
    # Width: ~16.5cm, Height: ~23.5cm
    A4_PRINT_WIDTH_PX = 624
    A4_PRINT_HEIGHT_PX = 888
    PAGE_ASPECT_RATIO = A4_PRINT_WIDTH_PX / A4_PRINT_HEIGHT_PX  # ~0.702

    # Regex patterns
    MERMAID_BLOCK_PATTERN = re.compile(r'```mermaid\s+(.*?)\s+```', re.DOTALL)
    
    def __init__(
        self,
        temp_dir: Optional[Union[str, Path]] = None,
        mermaid_url: str = DEFAULT_MERMAID_BASE_URL,
        template_path: Optional[Union[str, Path]] = None,
        request_timeout: int = DEFAULT_REQUEST_TIMEOUT
    ):
        """
        Initialize the converter.

        Args:
            temp_dir: Directory for temporary artifacts. Defaults to system temp.
            mermaid_url: Service URL for rendering Mermaid diagrams.
            template_path: Path to a custom Word reference template (ref doc).
            request_timeout: HTTP timeout for fetching diagrams.
        """
        self.temp_dir = Path(temp_dir) if temp_dir else Path(tempfile.gettempdir()) / "md_converter_temp"
        self.images_dir = self.temp_dir / "images"
        self.mermaid_url = mermaid_url.rstrip('/')
        self.template_path = Path(template_path) if template_path else None
        self.request_timeout = request_timeout

        # Initialize workspace
        self._ensure_directories()

    def _ensure_directories(self) -> None:
        """Creates necessary temporary directories."""
        self.temp_dir.mkdir(parents=True, exist_ok=True)
        self.images_dir.mkdir(parents=True, exist_ok=True)

    def _calculate_image_layout(self, img_path: Path) -> str:
        """
        Calculates optimal image dimensions to fit within A4 page margins.
        
        Strategy:
            - If image is wider than the page ratio (landscape), scale by width.
            - If image is taller than the page ratio (portrait), scale by height or cap width.
        
        Returns:
            Pandoc-compatible attribute string (e.g., "width=100%").
        """
        try:
            with Image.open(img_path) as img:
                width_px, height_px = img.size
                img_aspect_ratio = width_px / height_px

                if img_aspect_ratio > self.PAGE_ASPECT_RATIO:
                    # Image is wider relative to page shape
                    if width_px > self.A4_PRINT_WIDTH_PX:
                         return "width=100%"
                    else:
                        # Calculate percentage relative to max printable width
                        percent = int((width_px / self.A4_PRINT_WIDTH_PX) * 100)
                        return f"width={percent}%"
                else:
                    # Image is taller relative to page shape
                    if height_px > self.A4_PRINT_HEIGHT_PX:
                        return "height=23cm"
                    else:
                        return "width=80%"  # Safe default for portrait images

        except Exception as e:
            logger.warning(f"Could not calculate dimensions for {img_path.name}: {e}. Defaulting to width=100%.")
            return "width=100%"

    def _normalize_markdown_spacing(self, content: str) -> str:
        """
        Ensures proper spacing between elements for Pandoc parsing.
        
        Fixes common issues like:
        1. Missing newlines after bold text.
        2. Missing newlines after headers.
        3. Text 'sticking' to list items.
        """
        # 1. Ensure newline after bold text if not followed by list or newline
        # Logic: (**bold**\n) -> Ensure it acts as a paragraph break if needed
        content = re.sub(r'(\*\*.*?\*\*\n)(?!\n|\s*[\*\-\d]\.)', r'\1\n', content)

        # 2. Ensure newline after headers
        content = re.sub(r'^(#+ .*?\n)(?!\n)', r'\1\n', content, flags=re.MULTILINE)

        # 3. Separate text from list items with a blank line
        content = re.sub(r'([^\n])\n(\s*[\*\-\d]\. )', r'\1\n\n\2', content)

        return content

    def _download_mermaid_image(self, graph_code: str, unique_id: str) -> Optional[Path]:
        """Encodes graph code and fetches the rendered image from the API."""
        try:
            # Prepare payload
            graph_config = {
                "code": graph_code,
                "mermaid": {"theme": "default"}
            }
            json_str = json.dumps(graph_config)
            base64_str = base64.urlsafe_b64encode(json_str.encode('utf-8')).decode('utf-8')
            
            img_url = f"{self.mermaid_url}/{base64_str}"
            
            # Generate a deterministic but unique filename based on content hash
            content_hash = abs(hash(graph_code))
            img_name = f"mermaid_{unique_id}_{content_hash}.png"
            img_path = self.images_dir / img_name

            # Skip download if exists (caching strategy could be improved here)
            if img_path.exists():
                return img_path

            logger.info(f"Rendering diagram: {img_name}...")
            response = requests.get(img_url, timeout=self.request_timeout)
            
            if response.status_code == 200:
                img_path.write_bytes(response.content)
                return img_path
            else:
                logger.error(f"Failed to render diagram. Status: {response.status_code}")
                return None

        except Exception as e:
            logger.error(f"Error rendering diagram: {e}")
            return None

    def _process_mermaid_diagrams(
        self, 
        md_content: str, 
        unique_run_id: str,
        force_width: Optional[str] = None,
        force_height: Optional[str] = None,
    ) -> Tuple[str, List[Path]]:
        """
        Finds Mermaid blocks, renders them to images, and replaces the code blocks 
        with Markdown image links.
        
        Returns:
            Tuple of (Processed Markdown String, List of Generated Image Paths)
        """
        generated_images: List[Path] = []

        def replace_match(match: re.Match) -> str:
            graph_code = match.group(1).strip()
            img_path = self._download_mermaid_image(graph_code, unique_run_id)

            if not img_path:
                # Fallback: keep original code block if rendering fails
                return match.group(0)

            generated_images.append(img_path)

            # Determine layout attributes
            size_attrs = []
            if force_width:
                size_attrs.append(f"width={force_width}")
            if force_height:
                size_attrs.append(f"height={force_height}")
            
            if not size_attrs:
                # Auto-calculate if no overrides provided
                size_attrs.append(self._calculate_image_layout(img_path))

            attr_string = " ".join(size_attrs)
            # Use absolute path for Pandoc to find it reliably
            return f"\n\n![]({img_path.absolute()}){{{attr_string}}}\n\n"

        processed_content = self.MERMAID_BLOCK_PATTERN.sub(replace_match, md_content)
        return processed_content, generated_images

    def _cleanup(self, files: List[Path]) -> None:
        """Removes temporary files and directories if empty."""
        for file_path in files:
            try:
                if file_path.exists():
                    file_path.unlink()
                    logger.debug(f"Cleaned up: {file_path}")
            except OSError as e:
                logger.warning(f"Failed to delete {file_path}: {e}")

        # Attempt to remove image directory if empty
        try:
            if self.images_dir.exists() and not any(self.images_dir.iterdir()):
                self.images_dir.rmdir()
                logger.debug("Removed empty images directory.")
        except OSError:
            pass

    def convert(
        self,
        input_path: Union[str, Path],
        output_path: Union[str, Path],
        keep_intermediate: bool = False,
        cleanup: bool = True
    ) -> str:
        """
        Executes the conversion pipeline.

        Args:
            input_path: Path to source Markdown file.
            output_path: Destination path for DOCX file.
            keep_intermediate: If True, saves the processed Markdown file.
            cleanup: If True, deletes downloaded images after conversion.

        Returns:
            Path to the generated document as a string.
        """
        input_path = Path(input_path)
        output_path = Path(output_path)
        run_id = str(uuid.uuid4())[:8]
        temp_files_tracker: List[Path] = []

        if not input_path.exists():
            raise FileNotFoundError(f"Input file not found: {input_path}")

        try:
            logger.info(f"Starting conversion for {input_path.name}")
            content = input_path.read_text(encoding='utf-8')

            # 1. Render Diagrams
            processed_content, images = self._process_mermaid_diagrams(content, run_id)
            temp_files_tracker.extend(images)

            # 2. Normalize Formatting
            final_content = self._normalize_markdown_spacing(processed_content)

            # 3. (Optional) Save Intermediate Markdown
            if keep_intermediate:
                intermediate_path = self.temp_dir / f"processed_{run_id}_{input_path.name}"
                intermediate_path.write_text(final_content, encoding='utf-8')
                logger.info(f"Intermediate Markdown saved to: {intermediate_path}")
                # We do not add this to temp_files_tracker because the user asked to keep it
            else:
                # If we don't keep it user-visible, we still need a file for Pandoc
                # but we mark it for deletion
                temp_md = self.temp_dir / f"temp_{run_id}.md"
                temp_md.write_text(final_content, encoding='utf-8')
                temp_files_tracker.append(temp_md)
                # Point pandoc to this temp file
                source_file_path = str(temp_md)

            # Determine source for Pandoc
            source_file_path = str(self.temp_dir / f"processed_{run_id}_{input_path.name}") \
                if keep_intermediate else str(temp_files_tracker[-1])

            # 4. Run Pandoc
            extra_args = [
                "--standalone",
                "--toc",
                "--toc-depth=3",
            ]
            if self.template_path and self.template_path.exists():
                extra_args.append(f"--reference-doc={self.template_path}")
            else:
                logger.warning("Template path not provided or not found. Using default Word style.")

            pypandoc.convert_file(
                source_file=source_file_path,
                to='docx',
                outputfile=str(output_path),
                extra_args=extra_args
            )
            
            logger.info(f"Successfully generated: {output_path}")
            return str(output_path)

        except Exception as e:
            logger.error(f"Conversion failed: {e}")
            raise
        finally:
            if cleanup:
                logger.info("Cleaning up temporary files...")
                self._cleanup(temp_files_tracker)


def generate_default_template(output_name: str = "reference.docx") -> None:
    """Extracts Pandoc's default Word reference template."""
    try:
        pandoc_path = pypandoc.get_pandoc_path()
        logger.info(f"Using Pandoc at: {pandoc_path}")

        # Equivalent to: pandoc --print-default-data-file reference.docx > output_name
        result = subprocess.run(
            [pandoc_path, "--print-default-data-file", "reference.docx"],
            capture_output=True,
            check=True
        )
        
        Path(output_name).write_bytes(result.stdout)
        logger.info(f"Template generated: {output_name}")
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to extract template: {e}")
    except Exception as e:
        logger.error(f"An error occurred: {e}")


# ==========================================
# 全局默认实例 (Global Default Instance)
# ==========================================

# 实例化一个全局 MarkdownToDocxConverter 对象。
# 这是一个预配置的转换器，可供其他模块直接导入和使用。
# 默认行为：
# 1. 使用系统默认临时目录
# 2. 使用标准的 Mermaid 渲染服务 (mermaid.ink)
# 3. 不使用自定义 Word 模板 (使用 Pandoc 默认样式)
global_converter = MarkdownToDocxConverter()


if __name__ == "__main__":
    # Setup for demonstration/testing
    
    # Use relative paths for portability in this example
    base_dir = Path.cwd()
    sample_input = base_dir / "README.md"  # Replace with actual file
    sample_output = base_dir / "output.docx"
    sample_template = base_dir / "template.docx"

    # Create dummy file if it doesn't exist for testing
    if not sample_input.exists():
        sample_input.write_text(
            "# Test Document\n\nHere is a diagram:\n\n```mermaid\ngraph TD;\nA-->B;\n```\n", 
            encoding='utf-8'
        )
        print(f"Created dummy input file: {sample_input}")

    # Generate template if needed
    if not sample_template.exists():
        generate_default_template(str(sample_template))

    # Initialize and run
    # 注意：此处演示使用自定义配置实例化，而非使用上面的 global_converter
    converter = MarkdownToDocxConverter(
        template_path=sample_template
    )

    try:
        converter.convert(
            input_path=sample_input,
            output_path=sample_output,
            keep_intermediate=True,
            cleanup=False # Set to True to delete images after run
        )
    except Exception as e:
        logger.error(f"Main execution failed: {e}")
