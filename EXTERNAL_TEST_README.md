# Latest: provisional LVCMOS33 offline Bitstream (2026-10-29)

Build report: [results/external/provisional33_20261029_170940/PROVISIONAL33_BUILD_REPORT.md](results/external/provisional33_20261029_170940/PROVISIONAL33_BUILD_REPORT.md).
New constraint: external_sources/external_pins_lvcmos33_provisional.xdc, isolated new constraint set.
CH0/1/2/3 = U5/V7/W8/U9; LVCMOS33 is PROVISIONAL from the schematic.
J4 ordinary +3.3V reported 3.239V is NOT a measurement of VCCO_B13; actual supply/resistor fitting and J4 orientation remain unverified.
Offline Bitstream generated, NOT APPROVED FOR PROGRAMMING OR EXTERNAL WIRING.
WNS=4.562ns, WHS=0.023ns; zero build Critical Warnings and NSTD-1/UCIO-1 absent.
Other debug-IP DRC/methodology warnings remain in the reports. No waiver, downgrade, download or ELF overwrite.
The earlier prohibition on generating Bitstream was superseded only for this offline build by the user's 2026-10-29 instruction; hardware release is still blocked.
The following text is retained historical context; earlier no-pin/no-Bitstream status applies to earlier runs.

---

# 外部信号输入实验

工作根目录：`D:\FPGA_Projects\zynq_timing_diagnostic\vivado_ps_pl_2025_2_external_test`。
工程：根目录 `timing_diagnostic_ps_pl.xpr`；xc7z020clg400-2，Vivado/Vitis 2025.2，FCLK0=50MHz，AXI=0x43C00000。

**当前不具备上板放行条件。不得连接信号源或下载本次实验设计。** 管脚图纸核对已完成，但实板版本、排针方向、Bank13 实测 VCCO、信号实际幅度及 IOSTANDARD 均需确认。活动工程故意没有为外部端口指定封装脚和电平标准；探索性构建结果不可用于上板。

最新修复轮10/10仿真PASS，标准工程完成综合/布线，原188条构建Critical Warning降为0；WNS=+3.991ns，LUT=18273、FF=17621、BRAM=0.5、DSP=0。DRC仍有NSTD-1/UCIO-1及调试核普通警告，尚不能宣称除电压外全部上板准备完成。详见TEST_RESULTS.md和CRITICAL_WARNING_REPAIR.md；本阶段不生成/下载Bitstream，不接外部信号。

工作工程完整初始备份为 `external_backup_20261028_163818`，包含原始 XPR、HDL、生成文件、运行产物、日志和交付 Bitstream。原始 `wave_test` 工程仅作只读哈希核查。原始工程、已有 Bitstream/ELF、Phase2 ELF 和核心 HDL 完整性见 `results/external/isolation_verification.json`；保留初始清单用于重复验证。

输入路径仍为 `system.bd → timing_diagnostic_axi_bd_wrapper → timing_diagnostic_axi_top.async_ch → core_v3 → core_v2 → core → timing_measure_core → input_sync_edge`。仅 wrapper 增加 external_ch 和编译参数，已验证的核心模块全部保留。`internal_test_wave_gen` 保留在源码中，外部构建中未使用逻辑可能被综合优化。

默认 `EXTERNAL_MODE=1`、`EXTERNAL_ENABLE_MASK=15`；内部回退 `EXTERNAL_MODE=0`。模式与掩码只在编译时确定，无运行时切换接口，因此不存在切换 mux 引起的伪边沿。切换实验模式必须停止采集、重新构建、硬件放行后加载并复位，建立至少两个完整周期测量历史再判读。输入启动为高电平由既有同步器 warmup 抑制虚假首个上升沿，不改变原逻辑。

Vivado 的 `update_module_reference`、BD 端口连接、`generate_target` 和 `make_wrapper` 已实际运行；自动生成顶层未手工修改。DDR/FIXED_IO/AXI 地址不作更改。生成 wrapper 位于 `timing_diagnostic_ps_pl.gen/sources_1/bd/system/hdl/system_wrapper.v`。

软件采用独立 `external_software/external_monitor.c`。它不包含 UART 测试命令、阈值注入、FIFO pop 或清空；启动检查 ID/version/50MHz，要求诊断已关闭。唯一写入为 0x00C=2 的采集快照请求（同时保持 global_enable=0），其余为只读日志。因此“只读测量”指不修改诊断配置，**不是零 MMIO 写入**。此版寄存器需快照请求才能得到新测量，严格零写软件只能读取陈旧快照，不能冒充实时测量。应用应独占 AXI 配置，若发现诊断开启则停止并要求复位。

原 Phase2 软件默认诊断 OFF，但其菜单 `t` 和 `a` 等仍会运行固定内部波形故障用例；外部波形下这些阈值和期望值不成立。外部实验仅加载独立 external_monitor.elf，保留原 Phase2 ELF 用于原内部成功版本。不修改原软件或 ELF。

已有内部实板四通道与24/24 PASS 是用户提供的历史事实；本次仿真不得替代新增外部实测。所有当前通过/阻塞状态见 [TEST_RESULTS.md](TEST_RESULTS.md)，命令见 [BUILD_AND_TEST.md](BUILD_AND_TEST.md)，电气条件见 [PIN_MAP.md](PIN_MAP.md)。

首次 CH0 1kHz 实测顺序（仅在全部硬件条件满足后）：

1. 断开信号源，核实实板型号/版本、J4-1 标记和方向、J4-3 到 U5 连通性；核实地线。断电检查电源选配，上电测 Bank13 VCCO并留存照片/读数。
2. 按测量结果确定标准和允许的 VIH/VIL/输入范围。审查条件 XDC，选择 `mode=1 mask=1`，加入经审查的管脚/电平/下拉约束；重新综合、实现并检查 DRC、时序、CDC 后才可生成新的独立命名 Bitstream。不得覆盖旧成功版本。
3. 在信号源输出关闭时设置 1kHz、50%占空比、0V低电平及与标准匹配的高电平；确认 High-Z/50Ω 显示设置，示波器实测实际负载上的幅度、偏置、过冲和负压。禁止5V、禁止负电压直连。
4. 板卡与信号源共地后接 CH0 J4-3。其余通道逻辑屏蔽并处理悬空。仅使用通过上述检查的新 Bitstream 和独立外部采集 ELF；复位并启动115200 8N1串口日志，再开启信号输出。
5. 等待至少几个周期；预期 P=50000 ticks，H/L≈25000 ticks，频率≈1000Hz，占空比≈50%。20ns采样带来量化误差，异步相位可使宽度/周期相差约1 tick；实际误差还包括板卡时钟和信号源精度。不得宣称亚20ns分辨率或仅凭仿真宣称精度达标。
6. 保存原始UART日志、示波器截图、频率/幅度/偏置/电压/构建参数/Bitstream和ELF哈希。诊断关闭时 FIFO 应无新增故障。停波后可能保留上次测量，history有效不表示仍有信号；本只读版不自动启用超时诊断。
7. 关闭源输出后再改变接线；CH0通过后再逐通道扩展。外部故障阈值须依据实际波形另行设计、审查和显式启用，禁止运行原固定内部波形24项菜单。
