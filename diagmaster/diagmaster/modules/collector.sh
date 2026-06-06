#!/usr/bin/env bash
# 性能指标多进程后台并发采集器

DATA_DIR="./data"
mkdir -p "$DATA_DIR"

( top -bn1 | grep "Cpu(s)" | awk '{print $2+$4}' > "$DATA_DIR/cpu.tmp" ) & pid1=$!
( free -m | awk '/Mem:/ {print $3/$2*100}' > "$DATA_DIR/mem.tmp" ) & pid2=$!

# 【测试修改点】：注释掉真实磁盘采集，强行注入 95% 极值边界
# ( df -h / | awk 'NR==2 {print $5}' | sed 's/%//' > "$DATA_DIR/disk.tmp" ) & pid3=$!
echo "95" > "$DATA_DIR/disk.tmp" & pid3=$!

wait $pid1 $pid2 $pid3
