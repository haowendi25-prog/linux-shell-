#!/bin/bash

diagnose_disk() {
    DISK_CONCLUSION="正常"
    DISK_SUGGESTION="无需操作"

    if [ "$CURRENT_DISK" -gt "$DISK_THRESHOLD" ]; then
        DISK_CONCLUSION="警告：根分区磁盘空间即将耗尽 (${CURRENT_DISK}%)"
        DISK_SUGGESTION="根目录空间不足，可能会导致系统服务无法写入日志而崩溃。\n💡 建议命令：使用 'du -sh /* 2>/dev/null | sort -hr | head -n 5' 排查到底是哪个大目录占用了空间。"
    fi
}
