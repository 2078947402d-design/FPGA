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

# 外部输入管脚核对与电气放行条件

状态：原理图交叉核对通过；实板版本、排针方向和 Bank13 VCCO 未现场确认，禁止连接信号源或下载本次实验设计。

只有GA1102CAL与10X探针时的供电追踪、候选电气节点和不拆板验证路径，见 [VCCO_B13_MEASUREMENT_REVIEW.md](VCCO_B13_MEASUREMENT_REVIEW.md)。尚未找到经实物定位确认的安全VCCO_B13测点，不要求用户探触密集器件。

| 通道 | 底板 J4 引脚 | 网络 | 核心板底板连接器链路 | FPGA 球脚 | 核心板 Bank13 原名 |
|---|---|---|---|---|---|
| CH0 | 3 | B13_L19_N | 底板 J1-88 → 核心板 X4-88 | U5 | IO_L19N_T3_VREF_13 |
| CH1 | 5 | B13_L11_N | 底板 J1-84 → 核心板 X4-84 | V7 | IO_L11N_T1_SRCC_13 |
| CH2 | 7 | B13_L15_N | 底板 J1-80 → 核心板 X4-80 | W8 | IO_L15N_T2_DQS_13 |
| CH3 | 9 | B13_L17_P | 底板 J1-76 → 核心板 X4-76 | U9 | IO_L17P_T2_13 |

独立核查资料（绝对路径）：

- `D:\下载资料\桌面\fpga比赛资料\领航者ZYNQ底板原理图_V3.9.pdf`，PDF 第 5 页 IO：J4 左侧奇数 1/3/5/7/9，右侧偶数 2/4/6/8/10。同页 CORE_IO 将上述网络对应到 J1 的 88/84/80/76 与 U5/V7/W8/U9，未从用户候选表推导。
- `D:\下载资料\桌面\fpga比赛资料\ZYNQ7010_7020核心板原理图_2V5.pdf`，PDF 第 6 页 06_Bank_13：分别核对 U1E 的四个球脚和 IO 原名。第 12 页 12_CONNECTOR 独立核对 X4-88/84/80/76 网络。第 7 页 07_FPGA_POWER：VCCO_B13 接 Bank13 的 T8/W7/U11/Y10。
- 原图提取和渲染位于 `results/external/baseboard.txt`、`coreboard.txt`、`base_detail5.png`、`coreboard_page6.png`、`power_detail7.png`。PDF 文本含 Altium 隐藏网络数据，排针编号以可视图像核对。
- Vivado器件库第三方交叉信息保存于 `results/external/postcheck_20261028_171803/package_pins.txt`，四脚BANK均为13，PIN_FUNC与上表一致。这只是封装库核对，当前探索性实现没有把external_ch端口绑定到这些候选脚，不能使用自动分配的IO位置上板。

第 7 页图纸画出 R220/R222 为 VCCIO 支路 NC，R223/R221 为 +3.3V 支路 0R。**这是图纸配置，不能作为实板 VCCO 已确认的证据**；文件名中的 2V5 同样不能作为电压依据。现场检查实际电阻装配、核心板版本，断电检查连通性，上电用万用表测量 Bank13 实际 VCCO 并记录测点、读数、照片。J4-38 是底板 +3.3V，不能通过它推断 Bank13 VCCO；J4-40 为 +5V，严禁误接。J4-37/39 图纸为 GND，仍须现场核对方向和地连通性。

条件 XDC 为 `external_sources/external_pins.xdc.template`，未加入工程。只有实板管脚、电压均确认并在本文记录后才能复制为活动 XDC，将故意无效的 `UNVERIFIED_VCCO` 替换为经审查的合法标准。不预设 LVCMOS33/LVCMOS25。U5 兼有 VREF 功能，需确认本 Bank 没有需要占用此脚的参考电压标准；本设计按普通单端输入使用，P/N 字样不意味着必须差分连接。

输入电气范围必须按照测得的 VCCO、所选 IOSTANDARD 的 VIH/VIL 及 AMD DS187 推荐工作范围确定，目标低电平约 0V、高电平取匹配逻辑电压；还要实测过冲/负压，不能把绝对最大额定值当作可持续工作范围。参考 [AMD DS187](https://docs.amd.com/v/u/en-US/ds187-XC7Z010-XC7Z020-Data-Sheet)。严禁 5V 直连 PL IO，不使用双极性 ± 方波。需要时采用适配电平转换器；串联电阻不能代替电平转换。

信号源关闭输出后接线，设备与板卡共同接地，尽量短地线并用示波器在实际输入端检查幅度与偏置。信号源 50Ω 显示通常假定 50Ω 负载；接高阻 FPGA 输入时实际幅度可能约为显示的两倍，偏置也须实测。优先选择 High-Z 显示，并核查仪器手册和实际波形。不要随意在 PL 输入加 50Ω 终端。

悬空输入会随机翻转，三级同步不能消除悬空噪声。条件 XDC 为所有四路启用弱 PULLDOWN；硬件放行后确认其实际生效，必要时加合适外部下拉。首次只测 CH0 时建议编译 `EXTERNAL_ENABLE_MASK=1`，其余三路逻辑固定低；掩码是构建参数，不提供运行时切换。未接入通道不可用于故障判定。

现场记录（禁止用图纸推测值填写实测栏）：

| 确认项 | 本轮状态/待填记录 |
|---|---|
| 底板/核心板实物版本、J4-1方向 | 待现场确认 |
| J4-3/5/7/9到U5/V7/W8/U9连通性 | 图纸已核对；实板待确认 |
| R220/R222/R223/R221实际装配 | 待现场确认 |
| Bank13 VCCO测点、实测值、照片、日期 | 待现场测量 |
| 所选IOSTANDARD及DS187输入范围 | 待VCCO确认后审查 |
| 信号源型号、High-Z/50Ω模式、幅度与偏置 | 待记录并示波器验证 |
| IO端实际低/高电平、过冲、负压 | 待示波器验证 |
| 共地与未用通道屏蔽/下拉 | 待确认 |
| 审查后XDC、独立Bitstream/ELF哈希 | 尚未放行 |
| 首次CH0原始UART日志与示波器截图 | 未实测 |
