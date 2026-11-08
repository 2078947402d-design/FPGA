# Zynq-7020 竞赛代码提交副本

本目录从现有 external_test 工程独立复制。原工程保持只读；本次仅复制和哈希核对，没有启动 Vivado/Vitis、构建、仿真、串口或硬件调试，没有执行 Git 操作。

## 工程入口与目录

- 工具版本：AMD Vivado 2025.2；器件：xc7z020clg400-2；顶层：system_wrapper。
- 工程入口：timing_diagnostic_ps_pl.xpr。所有复制文件保持相对于该 XPR 的原目录关系。
- debug_sources/：当前工程 PL RTL、时序测量、故障检测、事件仲裁/FIFO、AXI 寄存器及 BD 封装。
- external_sources/：外部引脚约束、CDC 约束及调试 IP 配置；另有 .srcs/constrs_1/new/ila_debug.xdc。
- timing_diagnostic_ps_pl.srcs/：BD、XCI、约束和工程引用的导入检查点。
- timing_diagnostic_ps_pl.gen/：当前工程依赖的生成封装及 IP 输出，保留以避免丢失依赖。
- results/external/provisional33_20261029_170940/debug_cache/：XPR 的 IPOutputRepo 直接引用；虽然目录名含 cache，仍作为必要依赖保留。
- external_tb/、debug_tb/：对应仿真源码；external_scripts/run_sim.ps1 为既有仿真入口，check_cdc.tcl 为 XPR 引用钩子。本次未执行这些脚本。脚本中的本机工具路径可能需要在迁移环境人工核对。
- results/external/：精选原始验证状态报告、构建报告和历史 Bitstream 身份记录；并非全部历史档案的替代品。原始完整档案仍留在源工程。

## 打开与后续复现

在 Vivado 2025.2 中手动打开根目录 XPR。历史最终实现为 p001，对应综合 s33_20261029_171013、约束集 c33_20261029_171013；外部引脚使用 external_pins_lvcmos33_provisional.xdc。不要将旧 constrs_1 或历史运行误认为同一最终配置。

本次排除 .runs、.sim、.Xil、旧构建产物、WDB、临时文件、备份和重复工程。保留直接引用的生成依赖，但未在新目录运行 IP 生成、综合、实现或仿真，因此迁移后的完整重建状态为待确认。XPR 保留历史运行定义；缺少旧运行输出不表示源文件缺失。后续构建应在独立授权和配置核对后进行，本目录不提供自动构建或硬件下载动作。

## 已有验证范围与未完成事项

历史 PL 功能验证包含四通道独立测量、同源同时输入、双信号源并行、CH0 超时、CH0/CH1 双超时和 FIFO 两事件逐条消费。原报告的 PASS/FAIL 状态保持原文；PASS 仅限各报告所述条件。本次复制校验不构成新的构建或硬件验证。

首次 CH0 超时 FAIL 的根因仍 UNKNOWN；历史 CH2 Delta=17 ticks 异常根因仍未闭合。已发现的接线问题不证明所有历史异常均有相同根因。不得用后续 PASS 改写历史 FAIL。

设计目标 FCLK0 为 50MHz；历史硬件配置按标称 PS_CLK 推算约 36.11MHz，尚未独立校准。原始 P/H/L tick 及功能变化响应不能作为正式绝对精度校准结论。

PS/UART 板级闭环仍为 INCONCLUSIVE，CPU0 候选最小 ELF 的安全启动评估为 NO-GO，当前 ARM 应用身份和共享内存占用未确认。APU/AHB-AP0 调试器读取 CORE_ID 成功不能证明 ARM 程序主动访问 PL 或 UART 闭环成功。PS 候选应用和 Vitis 工作区不属于本次 PL 代码副本；BD 中 PS 配置及生成依赖仍保留。没有将任何 PS 候选应用标为已上板通过。

## 硬件安全边界

历史参考文件 external_4ch_LVCMOS33_PROVISIONAL_DO_NOT_PROGRAM.bit 的文件名和字节保持不变；SHA-256 为 8375FD218E52D1FE2615FF0BF8CD8FEF14C15772A260FD6EE13CC19D402487F3。

PROVISIONAL_DO_NOT_PROGRAM 是保留的安全限制，不是可下载发布版本。历史受控上板 PASS 不构成再次下载、烧写、复位、CPU 控制、PS 初始化或寄存器写入授权。Bank13 供电、LVCMOS33 约束、现场接线与电压安全边界仍需按原记录核对；不得根据本提交副本自动操作硬件。

## 文件核对

COPY_MANIFEST.csv 记录逐文件来源、纳入原因和复制前后 SHA-256。SHA256SUMS.txt 覆盖除其自身之外的副本文件。MISSING_ITEMS.txt 记录本次选择项缺失情况。新增 README 仅解释副本结构与状态，不修改任何原报告。
