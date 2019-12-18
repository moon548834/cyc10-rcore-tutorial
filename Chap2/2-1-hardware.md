# 硬件说明

## 一些背景知识

### 五级流水架构

![](/IMG/pipeline.png)

这只是一个简单的示意图，如果没有相关的基础知识理解起来还是比较困难的，我这里推荐一本书，名字是《计算机组成与设计——硬件软件接口》作者是Patterson和Hennessy，里面有详细的过于MIPS架构的介绍，事实上MIPS和RISCV从架构上讲都属于精简指令集，而且很多结构都比较相似，所以不必拘泥于一定要找riscv的书。另外如果接触源码的话，之前推荐的雷思磊写的是一本不错的书，不过学习过程不能只是抄源码，还是要多去理解才有更大的收获的。

在这里我结合本工程的CPU简单介绍一下一个指令的执行过程，对于一条指令来讲，在硬件执行的过程中被拆分成了5个阶段，这五个阶段在没有异常和暂停的时候是并行进行的。对于一个指令来说首先在IF阶段更新pc值并从指令ROM中取数据，这个时候由于数据可能需要若干周期，流水线就暂停了，等到请求完毕后将去回来的指令送往ID级，ID级的工作顾名思义就是decode的过程，接下来进入的是EXE也就是执行级，这里面一般会进行一些加减乘除移位的运算操作，然后将结果送往mem级，如果有访存的指令，那么就访问数据ram即可，同理，请求ram可能也需要多周期，此时流水线也停下。执行完毕后数据送往WB级，将结果写回寄存器堆。

需要注意的是，图中并没有标注处理中断异常的特权级，mips中是cp0，riscv中是csr，这个阶段一般都放在mem，一般来讲地址都需要进行mmu转换，一个访问ram的地址，需要先经过csr的一些判断，然后送往tlb，tlb出来的地址再送往(或者cache)内存。针对一些异常的情况，csr这个模块会及时地发出清流水线的命令，并进行相关处理。

> riscv的官方手册也是一个很好的帮助，另外国人也有一版电子书(翻译)介绍riscv架构的，在此也一并推荐 http://crva.io/documents/RISC-V-Reader-Chinese-v2p1.pdf

### wishbone总线

![](/IMG/wishbone.png)

wishbone总线只考虑单次的读写还是比较简单的，上面的端口比如 `rst`, `clk` 大多可以顾名思义，在此我也不赘述，握手协议简单地说就是 **CYC和STB同时拉高时表示请求开始，在整个过程中，保持高电平，一直等到slave响应ACK拉高后的下一周期，CYC，STB和ACK拉低，至此一个请求结束** 这里给一个简单的时序图(来自《自己动手写CPU》)，不考虑TAG信号，更详细资料请参阅 https://cdn.opencores.org/downloads/wbspec_b4.pdf 


![](/IMG/wishbone2.png)

> 请注意上升沿1和上升沿0之间实际可能还有若干个周期，并且ACK拉高的那个周期的上升沿CYC和STB还是高电平


## FPGA平台

小脚丫STEP-CYC10是一款基于Intel Cyclone10设计的FPGA开发板，芯片型号是10CL016YU256C8G。另外，板卡上集成了USB Blaster编程器、SDRAM、FLASH等多种外设。板上预留了PCIE子卡插座，可方便进行扩展。其板载资源如下：

| LE资源        | 16000   | 可扩展 STEP-PCIE接口      | 1个    |
| ------------- | ------- | ------------------------ | ------ |
| 片上存储空间   | 504Kbit | 集成 USB Blaster编程器    | 1个    |
| DSP blocks    | 56个    | SDRAM                    | 64Mbit |
| PLL           | 4路     | Flash                    | 64Mbit |
| Micro USB接口 | 2路     | 三轴加速度计 ADXL345      | 1个    |
| 数码管        | 4位     | USB转Uart桥接芯片 CP2102  | 1个    |
| RGB 三色LED   | 2个     | 12M与50M双路时钟源        | 1个    |
| 5向按键       | 1路     | LED                      | 8路    |

> 5向按键(?)我当成普通按键处理

## SOC整体框图

![](/IMG/soc.png)

## 硬件地址空间分配

基于以上资源，我将**测试环境**下的CPU地址分配如下：

| 设备   | 地址分布                | 大小 |
| ------ | ----------------------- | ---- |
| ROM    | 0x0001_0000~0x0001_c000 | 48KB |
| SDRAM  | 0x0010_0000~0x0050_0000 | 4MB |
| 串口   | 0x0200_0000~0x0200_0020 | 32B  |
| LED    | 0x0300_0000~0x0300_0010 | 16B  |

该部分可以在 `./wishbone_cyc10/phy_bus_addr_conv.v`中找到对应的verilog语句及宏定义，只需修改其中的数值即可。举个例子，如想修改RAM的地址分配，只需要修改以下两个宏即可，其余不需更改。

```verilog
`define RAM_PHYSICAL_ADDR_BEGIN            34'h00010_0000
`define RAM_PHYSICAL_ADDR_LEN              34'h00040_0000
```
## ROM控制器

相关代码位于 `./wishbone_cyc10/rom_wishbone.v`，相关控制比较简单，不赘述，单举一个需要注意的事项，这里我的ROM里面调用了一个已经封装好的IP核，这个IP核的配置为 深度=16384，宽度=32bits，这样算起来一共有64kB，与之前的48KB不符。这是因为IP核深度只能配置为16384/8192，即64KB/32KB，没有中间选项，所以只好如此，但并不影响结果，只要你保证真正用到的rom不超过48KB即可。或者配置为8192也可以，这样程序限制在小于32KB。

## 仿真环境的RAM控制器

通过开启或关闭 位于`./wishbone_cyc10/cpu/defines.v`中的宏``define Simulation`可以开启或关闭仿真环境，在仿真环境下使用的是如下定义的ram。

```verilog
reg [`WishboneDataBus] mem[0:`DataMemNum-1]; 
```

这里面 DataMemNum 是一个很大的数，所以综合必定失败，但是由于我们只是用来仿真，所以不必要求综合。但在进行联合仿真的时候 Tools -> Run Simulation Tool -> RTL Simulation，有时系统会报错，大意是必须先进行sythesis再仿真，这时我的做法是把ram中的DataMemNum数值调小，先保证综合成功，然后仿真的时候再改回原来的大数值就可以了。

## 真实环境的SDRAM控制器

### SDRAM结构

SDRAM(Synchronous Dynamic Random Access Memory)是同步动态随机访问存储器，同步是指memory工作需要同步时钟，内部命令的发送与数据的传输都以它为基准；动态是指存储阵列需要不断地刷新以保证数据不丢失；随机访问是指数据不是线性依次读写，而是可以自由指定地址进行读/写。

SDRAM的内部有存储单元整列，给出行地址，列地址，就可以选择相应的存储单元，如下图中右侧部分所示。

![](/IMG/sdram_frame.png)

图上左侧的信号，对应于顶层文件的这些接口，有部分信号芯片手册上未标明如dq。 

```verilog
   output wire 			sdr_clk_o,
   output wire 			sdr_cs_n_o,
   output wire		   	sdr_cke_o,
   output wire 			sdr_ras_n_o,
   output wire 			sdr_cas_n_o,
   output wire 			sdr_we_n_o,
   output wire  [1:0] 	sdr_dqm_o,
   output wire  [1:0] 	sdr_ba_o,
   output wire	[11:0]  sdr_addr_o,
   inout  wire	[15:0]  sdr_dq_io,
```

接口说明如下：

| 序号   | 接口名  | 宽度(bit) |   输入/输出 | 作用
| ----- | ------  | ----      |   -----    | ----------------
| 1     | ADDR    | 12        |   输入      | 地址线
| 2     | CLK     | 1         |   输入      | 时钟
| 3     | CKE     | 1         |   输入      | 时钟使能
| 4     | RAS     | 1         |   输入      | 行地址选通，低有效
| 5     | CS      | 1         |   输入      | 片选，低有效
| 6     | CAS     | 1         |   输入      | 列地址选通，低有效
| 7     | WE      | 1         |   输入      | 写使能，低有效
| 8     | DQM     | 2         |   输入      | 字节选择和输出使能，低有效
| 9     | DQ      | 16        |   双向      | 数据线
| 10    | BA      | 2         |   输入      | bank选择

对于SDRAM更深刻的介绍，需要很大的篇幅，由于我们并非需要直接驱动SDRAM，而只需要驱动SDRAM的控制器，所以这里就不再展开，《自己动手写CPU》中关于Flash控制器有更多的描述。这里介绍的目的是，对SDRAM有一个基本的认识即可。

### SDRAM控制器

这个SDRAM控制器取自于OpenCores,该SDRAM控制器：
- 支持SDRAM的数据总线宽度可以为8,16,32
- 支持4个Bank的SDRAM
- 自动控制刷新
- 支持所有标准的SDRAm功能
- 支持 wishbone B总线

这是一个功能十分完善的控制器，根据说明，在实际使用过程中，**无需修改如何源码**我们只需配置如下参数就可以用了！


| 序号   | 参数名            | 宽度(bit) |   输入/输出 | 作用                                  |
| ----- | ----------------  | --------  |   -----    | -----------------------------------  |
| 1     | cfg_sdr_width     | 2         |   输入      | SDRAM的数据总线宽度:<br />   00 —— 32位SDRAM<br />  01 —— 16位SDRAM<br />  1x —— 8位SDRAM   | 
| 2     | cfg_sdr_en        | 1         |   输入      | SDRAM控制器使能信号                                                       |
| 3     | cfg_sdr_colbits   | 2         |   输入      | 列地址宽度:<br />00 —— 8bit<br /> 01 —— 9bit<br /> 10 —— 10bit<br />11 —— 11bit             |      
| 4     | cfg_sdr_mode_reg  | 13        |   输入      | 模式寄存器                                                                |
| 5     | cfg_sdr_tras_d    | 4         |   输入      | tRAS的值，单位是时钟周期                                                   |
| 6     | cfg_sdr_trp_d     | 4         |   输入      | tRP的值，单位是时钟周期                                                    |
| 7     | cfg_sdr_trcd_d    | 4         |   输入      | tRCD的值，单位是时钟周期                                                   |
| 8     | cfg_sdr_cas       | 3         |   输入      | CL地值，单位是时钟周期                                                     |
| 9     | cfg_sdr_trcar_d   | 4         |   双向      | tRC的值，单位是时钟周期                                                    |
| 10    | cfg_sdr_twr_d     | 4         |   输入      | tWR的值，单位是时钟周期                                                    |
| 11    | cfg_sdr_rfsh      | 12        |   输入      | 自动刷新间隔，单位是时钟周期                                                |
| 12    | cfg_sdr_rfmax     | 3         |   输入      | 每次刷新的最大行数                                                         |
| 13    | cfg_req_depth     | 2         |   输入      | 请求缓存的数量                                                            |

### SDRAM参数确定

那么接下来就是通过查阅手册来确定这些参数了：

前三个比较好确定，宽度是16，所以值是 2'b11； 使能自然是1'b1；列地址宽度是8，所以值是2'b00。

关于模式寄存器的结构如下，或者查阅芯片手册：

![](/IMG/sdram_config_mode_reg.png)

模式寄存器配置为 `13'b0_0000_0011_0001`，表示CAS延时为3个时钟周期，突发长度为2(一次16bits，两次正好32bits)，突发模式是线性。

关于有关时间的参数，见下表，或者查阅芯片手册进行配置。

> 手册中给出的-5 -6 -7代表了不同频率的设置值，最低的也是133MHz，事实上我在下板的时候用133MHz也会报WNS违约，后来发现**降低SDRAM主频**也是可以工作的。

![](/IMG/sdram_config_time.png)

> 参考《自己动手写CPU》cfg_sdr_cas要比模式寄存器中的值大一，故是3'b100。

关于rfsh的配置：芯片45S16400的每个bank有4096行，此处设置每次最大的刷新行数rfmax为4，所以在64ms内要求有 4096/4 = 1024 次刷新。每次刷新的间隔即是(64/1024)ms，SOC使用的时钟频率是30MHz，计算 30 * 1e6 * 64 * 1e-3 * / 1024 得到1875，故设置为对应的二进制 12'b011101010011。 

cfg_req_depth尚不清楚有何影响，采取和《自己动手写CPU》相同设置未发现错误。

最后的参数如下：

```verilog
    .cfg_req_depth(2'b11),
    .cfg_sdr_en(1'b1),
    .cfg_sdr_mode_reg(13'b0000000110001),
    .cfg_sdr_tras_d(4'b1000),
    .cfg_sdr_trp_d(4'b0010),
    .cfg_sdr_trcd_d(4'b0010),
    .cfg_sdr_cas(3'b100),
    .cfg_sdr_trcar_d(4'b1010),
    .cfg_sdr_twr_d(4'b0010),
    .cfg_sdr_rfsh(12'b011101010011),
    .cfg_sdr_rfmax(3'b100),
    .cfg_sdr_width(2'b01),
    .cfg_colbits(2'b00)
```

## uart控制器

uart帧格式比较简单，在本工程下，停止位1位，无校验位，波特率115200。

为了节约资源，目前的uart控制器只包含发送功能，且波特率硬件写死为115200(不符合UART16550协议)，(在仿真环境下为了加快速度，调成250_0000)。需要注意的是，uart在仿真的时候需要在接受端模拟一个串口。位于`simulation/modelsim/wishbone_soc.vt`，这个代码修改自lkx的工作，大体的意思是在每个比特发送的中间时刻进行采样，最后形成字节，并使用`$write("%c", rx_byte);`从而回显在modelsim上。

如果需要修改波特率，除了在SOC中修改波特率外，仿真条件下，在测试文件也需要进行修改，主要是以下两个常量：

```verilog
localparam CfgDivider    = 25000000/2500000;
localparam CfgDividerMid = CfgDivider/2;
```

> 在下板的时候，可以用putty等软件进行串口回显。putty是一个轻量级的软件，简单好用，推荐

## PLL控制器

在本工程中，使用quartus IP核配置进行配置，说明如下


| 信号名称      |  时钟频率 | 用途           |
| ----------   | -------- | -------------  |
| clk          | 12MHz    | 板载晶振输入时钟 |
| wishbone_clk | 25MHz    | 系统总线时钟    |
| cpu_clk      | 10MHz    | cpu时钟        |

这里的时钟频率并不是很高，主要是为了布线时消除时序违约，实际上可能可以再快一点也不会有WNS错误。

另外，PLL出来有一个 `lock` 信号，将它和复位信号进行与运算 `assign reset_n = lock & rst_n;` 可以避免一些时序问题。

> 注意没当修改总线频率之后，相应的uart模块中传递的参数也要修改(如下部分)，否则可能uart工作不正常。

```verilog
	wishbone_uart_lite #(
		.ClkFreq(25000000),
	`ifdef Simulation
		.BoundRate(2500000)
	`else
		.BoundRate(115200)
	`endif
	) 
```

