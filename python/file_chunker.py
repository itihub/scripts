#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
大文件拆分与合并工具 (File Chunker)
-------------------------------------------------------
功能：将大文件按指定大小拆分为多个小块，并通过元数据清单安全合并。
说明：所有的文件路径和目录参数，均原生支持相对路径与绝对路径。

特性：
- 流式处理 (低内存占用)
- [升级] 细粒度 SHA-256 数据完整性校验 (支持单块 Hash 校验与总 Hash 校验)
- 基于清单的安全重组机制
- 失败快速熔断与深度错误盘点 (支持终端自适应对齐表格渲染)

使用方法 (Usage):
-------------------------------------------------------
1. 拆分 (Split):
   $ python file_chunker.py split backup.zip -s 50M -o ./chunks/

2. 合并 (Merge - 遇到错误快速中断):
   $ python file_chunker.py merge ./chunks/backup.zip.meta.json -o ./output/

3. 深度校验 (Verify - 扫描所有块，打印损坏清单，不合并):
   $ python file_chunker.py verify ./chunks/backup.zip.meta.json
"""

import os
import sys
import json
import hashlib
import logging
import argparse
import unicodedata
from pathlib import Path
from typing import Generator, Optional, List

# ==========================================
# 常量定义 (Constants)
# ==========================================
DEFAULT_BUFFER_SIZE_BYTES = 8 * 1024 * 1024 
CHUNK_EXTENSION_FORMAT = ".part{:04d}"
META_EXTENSION = ".meta.json"

# ==========================================
# 日志配置 (Logging Configuration)
# ==========================================
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger("FileChunker")

# ==========================================
# 辅助工具模块 (Utility Module)
# ==========================================
class FileUtils:
    """提供通用的文件流操作与数据处理辅助方法"""
    
    @staticmethod
    def parse_size_string(size_str: str) -> int:
        size_str = size_str.strip().upper()
        if size_str.endswith('G') or size_str.endswith('GB'):
            return int(float(size_str.replace('GB', '').replace('G', '')) * 1024**3)
        elif size_str.endswith('M') or size_str.endswith('MB'):
            return int(float(size_str.replace('MB', '').replace('M', '')) * 1024**2)
        elif size_str.endswith('K') or size_str.endswith('KB'):
            return int(float(size_str.replace('KB', '').replace('K', '')) * 1024)
        elif size_str.isdigit():
            return int(size_str)
        else:
            raise ValueError(f"无法解析的大小格式: {size_str}。请使用 K, M, G 后缀。")

    @staticmethod
    def stream_read_with_hash(
        file_obj, 
        bytes_to_read: int, 
        hash_algos: Optional[List['hashlib._Hash']] = None,
        buffer_size: int = DEFAULT_BUFFER_SIZE_BYTES
    ) -> Generator[bytes, None, None]:
        """
        安全、流式地读取指定字节数的数据。
        支持同时传入多个 hash 对象（例如：一个计算总哈希，一个计算单块哈希），实现 DRY & 高效 IO。
        """
        bytes_read = 0
        while bytes_read < bytes_to_read:
            chunk_size = min(buffer_size, bytes_to_read - bytes_read)
            data_chunk = file_obj.read(chunk_size)
            
            if not data_chunk:
                break
                
            if hash_algos:
                for algo in hash_algos:
                    algo.update(data_chunk)
                
            bytes_read += len(data_chunk)
            yield data_chunk

    @staticmethod
    def get_display_width(text: str) -> int:
        """计算包含中英文字符的字符串在终端的实际视觉宽度"""
        width = 0
        for char in str(text):
            # 'W' (Wide) 和 'F' (Fullwidth) 代表中日韩等宽字符，占用2个视觉宽度
            if unicodedata.east_asian_width(char) in ('W', 'F'):
                width += 2
            else:
                width += 1
        return width

    @staticmethod
    def pad_text(text: str, width: int) -> str:
        """根据视觉宽度填充空格，实现中英文混合排版的完美对齐"""
        text = str(text)
        padding_len = max(0, width - FileUtils.get_display_width(text))
        return text + " " * padding_len

# ==========================================
# 核心业务逻辑模块 (Core Logic Module)
# ==========================================
class SecureFileSplitter:
    """负责大文件的安全拆分及元数据生成"""
    
    def __init__(self, source_filepath: Path, chunk_size_bytes: int, output_dir: Optional[Path] = None):
        self.source_filepath = source_filepath
        self.chunk_size_bytes = chunk_size_bytes
        self.output_dir = output_dir or source_filepath.parent
        
    def _validate_preconditions(self):
        if not self.source_filepath.exists():
            raise FileNotFoundError(f"源文件不存在: {self.source_filepath}")
        if not self.source_filepath.is_file():
            raise ValueError(f"目标不是一个文件: {self.source_filepath}")
        if self.chunk_size_bytes <= 0:
            raise ValueError("分块大小必须大于0")
            
        if not self.output_dir.exists():
            try:
                self.output_dir.mkdir(parents=True, exist_ok=True)
                logger.info(f"已创建输出目录: {self.output_dir}")
            except Exception as e:
                raise OSError(f"无法创建输出目录 {self.output_dir}: {e}")
            
    def execute(self):
        self._validate_preconditions()
        
        file_size = self.source_filepath.stat().st_size
        total_chunks = (file_size + self.chunk_size_bytes - 1) // self.chunk_size_bytes
        
        logger.info(f"开始拆分文件: {self.source_filepath.name}")
        logger.info(f"输出目录: {self.output_dir}")
        logger.info(f"文件总大小: {file_size} Bytes")
        logger.info(f"预估分块数: {total_chunks}")
        
        file_hash = hashlib.sha256()
        chunk_manifest = []

        try:
            with open(self.source_filepath, 'rb') as src_file:
                for chunk_index in range(1, total_chunks + 1):
                    chunk_filename = f"{self.source_filepath.name}{CHUNK_EXTENSION_FORMAT.format(chunk_index)}"
                    chunk_filepath = self.output_dir / chunk_filename
                    
                    logger.info(f"正在写入分块 [{chunk_index}/{total_chunks}]: {chunk_filename}")
                    
                    chunk_actual_size = 0
                    chunk_hash = hashlib.sha256()  # 新增：记录当前独立分块的 Hash
                    
                    with open(chunk_filepath, 'wb') as chunk_file:
                        # 同时更新总 Hash (file_hash) 和 独立分块 Hash (chunk_hash)
                        for data in FileUtils.stream_read_with_hash(src_file, self.chunk_size_bytes, [file_hash, chunk_hash]):
                            chunk_file.write(data)
                            chunk_actual_size += len(data)
                    
                    chunk_manifest.append({
                        "index": chunk_index,
                        "filename": chunk_filename,
                        "size": chunk_actual_size,
                        "sha256": chunk_hash.hexdigest()  # 将分块 Hash 写入元数据清单
                    })
                    
            self._generate_metadata(file_size, file_hash.hexdigest(), total_chunks, chunk_manifest)
            logger.info("✅ 拆分完成，已生成带单块哈希签名的元数据校验文件。")
            
            # --- 新增：打印系统原生合并命令 ---
            self._print_native_merge_commands()
            
        except (OSError, IOError) as e:
            logger.error(f"❌ 拆分过程中发生系统 IO 错误: {e}")
            sys.exit(1)

    def _generate_metadata(self, file_size: int, file_hash: str, total_chunks: int, chunk_manifest: list):
        meta_filepath = self.output_dir / f"{self.source_filepath.name}{META_EXTENSION}"
        metadata = {
            "version": "1.1", # 标记版本以支持单块 Hash
            "original_filename": self.source_filepath.name,
            "original_size_bytes": file_size,
            "original_sha256": file_hash,
            "total_chunks": total_chunks,
            "chunk_size_bytes": self.chunk_size_bytes,
            "manifest": chunk_manifest
        }
        
        with open(meta_filepath, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=4, ensure_ascii=False)
        logger.info(f"已保存元数据清单: {meta_filepath.name}")

    def _print_native_merge_commands(self):
        """打印脱离本脚本的系统原生合并命令"""
        out_dir_escaped = str(self.output_dir.absolute())
        file_name = self.source_filepath.name
        part_wildcard = CHUNK_EXTENSION_FORMAT.replace('{:04d}', '*')
        
        print("\n" + "=" * 65)
        print("💡 逃生舱提示：如果目标服务器没有 Python 环境，")
        print("您可以直接复制以下原生命令进行安全合并 (不依赖本脚本)：")
        print("-" * 65)
        print("👉 [Linux / macOS]:")
        print(f"   cd \"{out_dir_escaped}\" && cat \"{file_name}\"{part_wildcard} > \"{file_name}\"")
        print("-" * 65)
        print("👉 [Windows CMD]:")
        print(f"   cd /d \"{out_dir_escaped}\" & copy /b \"{file_name}\"{part_wildcard} \"{file_name}\"")
        print("=" * 65 + "\n")


class SecureFileMerger:
    """负责解析元数据并安全重组文件"""
    
    def __init__(self, meta_filepath: Path, output_dir: Optional[Path] = None):
        self.meta_filepath = meta_filepath
        self.source_dir = meta_filepath.parent
        self.output_dir = output_dir or self.source_dir
        
    def _load_and_validate_metadata(self, strict: bool = True) -> dict:
        """
        加载元数据。
        如果 strict 为 True，会在此时抛出文件丢失和大小异常的致命错误 (适用于 Merge 模式)。
        如果 strict 为 False，则跳过文件检查，将异常留给后续环节处理 (适用于 Verify 盘点模式)。
        """
        if not self.meta_filepath.exists():
            raise FileNotFoundError(f"未找到元数据文件: {self.meta_filepath}")
            
        with open(self.meta_filepath, 'r', encoding='utf-8') as f:
            metadata = json.load(f)
            
        if strict:
            logger.info("执行基础前置校验 (验证文件是否存在及大小)...")
            for chunk in metadata.get("manifest", []):
                chunk_file = self.source_dir / chunk["filename"]
                if not chunk_file.exists():
                    raise FileNotFoundError(f"缺失分块文件: {chunk_file.name}。无法进行操作！")
                if chunk_file.stat().st_size != chunk["size"]:
                    raise ValueError(f"分块文件大小异常: {chunk_file.name} (预期: {chunk['size']}, 实际: {chunk_file.stat().st_size})")
                
        return metadata

    def verify_all_chunks(self):
        """
        深度盘点模式：扫描所有块的 Hash/缺失状态，汇总错误，最后以视觉对齐的 Markdown 表格打印。
        """
        # strict=False，允许在盘点模式下优雅处理文件缺失的情况，而不是直接崩溃
        metadata = self._load_and_validate_metadata(strict=False)
        manifest = metadata.get("manifest", [])
        total_chunks = metadata["total_chunks"]
        
        corrupted_chunks = []
        logger.info(f"开始深度盘点 {total_chunks} 个分块的状态及 SHA-256 哈希值...")

        for idx, chunk in enumerate(manifest, 1):
            chunk_filepath = self.source_dir / chunk["filename"]
            expected_hash = chunk.get("sha256")
            
            if not expected_hash:
                logger.warning(f"分块 {chunk['filename']} 缺失哈希签名 (可能是旧版拆分工具生成)，跳过校验。")
                continue

            # 1. 拦截文件丢失错误
            if not chunk_filepath.exists():
                corrupted_chunks.append({
                    "index": idx,
                    "filename": chunk['filename'],
                    "expected": "文件应存在",
                    "actual": "❌ 文件丢失 (Missing)"
                })
                logger.error(f"❌ 分块丢失: {chunk['filename']}")
                continue

            # 2. 拦截文件大小异常
            if chunk_filepath.stat().st_size != chunk["size"]:
                corrupted_chunks.append({
                    "index": idx,
                    "filename": chunk['filename'],
                    "expected": f"大小: {chunk['size']} 字节",
                    "actual": f"❌ 大小截断: {chunk_filepath.stat().st_size} 字节"
                })
                logger.error(f"❌ 分块大小异常: {chunk['filename']}")
                continue

            # 3. 计算并对比哈希
            actual_hash_obj = hashlib.sha256()
            with open(chunk_filepath, 'rb') as f:
                for _ in FileUtils.stream_read_with_hash(f, chunk["size"], [actual_hash_obj]):
                    pass
            
            actual_hash_str = actual_hash_obj.hexdigest()
            if actual_hash_str != expected_hash:
                corrupted_chunks.append({
                    "index": idx,
                    "filename": chunk['filename'],
                    "expected": expected_hash,
                    "actual": actual_hash_str
                })
                logger.error(f"❌ 分块损坏: {chunk['filename']} (Hash不匹配)")
            else:
                sys.stdout.write(f"\r✅ 已通过校验: {idx}/{total_chunks}")
                sys.stdout.flush()

        print() # 换行
        if corrupted_chunks:
            logger.error(f"深度校验完成。发现 {len(corrupted_chunks)} 个异常分块！\n")
            
            # --- 动态计算列宽并使用自适应格式渲染对齐表格 ---
            headers = ["序号", "异常的分块文件名", "预期状态 (Expected)", "实际状态 (Actual)"]
            rows = [
                [str(c['index']), c['filename'], c['expected'], c['actual']]
                for c in corrupted_chunks
            ]

            # 遍历数据，找到每列的视觉最大宽度
            col_widths = [FileUtils.get_display_width(h) for h in headers]
            for row in rows:
                for i, cell in enumerate(row):
                    col_widths[i] = max(col_widths[i], FileUtils.get_display_width(cell))

            # 渲染表头
            header_str = "| " + " | ".join(FileUtils.pad_text(h, col_widths[i]) for i, h in enumerate(headers)) + " |"
            print(header_str)

            # 渲染 Markdown 分隔线
            sep_str = "|" + "|".join("-" * (col_widths[i] + 2) for i in range(len(headers))) + "|"
            print(sep_str)

            # 渲染数据行
            for row in rows:
                row_str = "| " + " | ".join(FileUtils.pad_text(cell, col_widths[i]) for i, cell in enumerate(row)) + " |"
                print(row_str)

            print("\n💡 提示：您可以直接复制上述表格粘贴到支持 Markdown 的工具中。")
            print("请根据上表重新传输对应的损坏/丢失的分块。")
            sys.exit(1)
        else:
            logger.info("深度校验完成。所有分块数据完好无损，可安全执行 merge 操作！")

    def execute(self):
        """
        合并模式：边合并边校验单块，遇到错误直接中断，防止无效 IO
        """
        try:
            # 合并模式下保持严格校验，文件一旦缺失或大小不对立即中止
            metadata = self._load_and_validate_metadata(strict=True)
            
            output_filename = metadata["original_filename"]
            output_filepath = self.output_dir / output_filename
            
            if output_filepath.exists():
                logger.warning(f"目标文件 {output_filename} 已存在。为了安全，将其重命名合并。")
                output_filepath = self.output_dir / f"merged_{output_filename}"

            logger.info(f"开始重组文件，输出至: {output_filepath}")
            
            merged_hash = hashlib.sha256()
            total_chunks = metadata["total_chunks"]
            manifest = metadata["manifest"]
            
            with open(output_filepath, 'wb') as out_file:
                for idx, chunk in enumerate(manifest, 1):
                    chunk_filepath = self.source_dir / chunk["filename"]
                    logger.info(f"正在合并分块 [{idx}/{total_chunks}]: {chunk['filename']}")
                    
                    chunk_hash = hashlib.sha256()
                    with open(chunk_filepath, 'rb') as chunk_file:
                        # 同时计算总 Hash 和 单块 Hash
                        for data in FileUtils.stream_read_with_hash(chunk_file, chunk["size"], [merged_hash, chunk_hash]):
                            out_file.write(data)
                    
                    # 快速熔断 (Fail-Fast) 机制：合并完当前块立刻校验，如果不对立刻中断
                    expected_chunk_hash = chunk.get("sha256")
                    if expected_chunk_hash and chunk_hash.hexdigest() != expected_chunk_hash:
                        logger.error(f"\n❌ 合并中断！检测到分块数据损坏: {chunk['filename']}")
                        logger.error("为节省磁盘资源，已终止合并任务。")
                        out_file.close()
                        # 安全清理掉残缺的输出文件
                        os.remove(output_filepath)
                        logger.info("已清理不完整的合并文件，请使用 verify 命令排查或者重新获取损坏的块。")
                        sys.exit(1)
                            
            # 终极校验：比对全文件哈希值 (防御某些不可预见的拼接错误)
            final_hash_str = merged_hash.hexdigest()
            expected_hash = metadata["original_sha256"]
            
            if final_hash_str != expected_hash:
                logger.error(f"❌ 严重错误: 文件总哈希校验失败！\n预期: {expected_hash}\n实际: {final_hash_str}")
                sys.exit(1)
            else:
                logger.info("✅ 文件重组成功并完成 SHA-256 校验。哈希值匹配完美！")
                
        except json.JSONDecodeError:
            logger.error(f"❌ 元数据文件损坏或不是有效的 JSON: {self.meta_filepath}")
        except Exception as e:
            logger.error(f"❌ 合并过程中发生异常: {e}")
            sys.exit(1)

# ==========================================
# 命令行接口 (Command Line Interface)
# ==========================================
def main():
    # 直接利用文件头部的 __doc__ 注释作为主说明，实现代码与文档统一
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawTextHelpFormatter
    )
    
    # 优化子命令的提示层级
    subparsers = parser.add_subparsers(
        title="子命令 (Subcommands)", 
        dest="command", 
        required=True,
        help="提示: 输入 'python file_chunker.py <子命令> -h' 可查看具体参数"
    )
    
    # 拆分命令 (Split Command)
    split_parser = subparsers.add_parser("split", help="将大文件拆分为多个部分", formatter_class=argparse.RawTextHelpFormatter)
    split_parser.add_argument("file", type=str, help="需要拆分的源文件路径")
    split_parser.add_argument(
        "-s", "--size", 
        type=str, 
        default="100M", 
        help="每个分块的大小 (支持格式: 500K, 50M, 1G)。\n默认: 100M"
    )
    split_parser.add_argument(
        "-o", "--output-dir", 
        type=str, 
        help="拆分后文件的保存目录。\n(如果不传，默认为源文件所在的同级目录)"
    )
    
    # 合并命令 (Merge Command)
    merge_parser = subparsers.add_parser("merge", help="合并文件 (边合并边校验，遇错立即中断)", formatter_class=argparse.RawTextHelpFormatter)
    merge_parser.add_argument("meta_file", type=str, help="由拆分时生成的 .meta.json 清单文件路径")
    merge_parser.add_argument(
        "-o", "--output-dir", 
        type=str, 
        help="合并后文件的保存目录。\n(如果不传，默认为 .meta.json 所在的同级目录)"
    )

    # 校验命令 (Verify Command)
    verify_parser = subparsers.add_parser("verify", help="深度校验盘点 (只读不写盘，扫描汇总损坏分块)", formatter_class=argparse.RawTextHelpFormatter)
    verify_parser.add_argument("meta_file", type=str, help="由拆分时生成的 .meta.json 清单文件路径")

    args = parser.parse_args()

    try:
        if args.command == "split":
            source_path = Path(args.file)
            chunk_bytes = FileUtils.parse_size_string(args.size)
            output_directory = Path(args.output_dir) if args.output_dir else None
            
            splitter = SecureFileSplitter(source_path, chunk_bytes, output_directory)
            splitter.execute()
            
        elif args.command == "merge":
            meta_path = Path(args.meta_file)
            output_directory = Path(args.output_dir) if args.output_dir else None
            
            merger = SecureFileMerger(meta_path, output_directory)
            merger.execute()
            
        elif args.command == "verify":
            meta_path = Path(args.meta_file)
            merger = SecureFileMerger(meta_path)
            merger.verify_all_chunks()
            
    except KeyboardInterrupt:
        logger.warning("\n用户强制中断了操作。")
        sys.exit(130)
    except Exception as e:
        logger.error(f"执行失败: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()