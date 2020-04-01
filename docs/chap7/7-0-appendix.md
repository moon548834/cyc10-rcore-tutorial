# 附录

## 使用OpenCores的SDRAM
**另外这个方式使用的开源的sdram程序，不是IP核**

SDRAM(Synchronous Dynamic Random Access Memory)是同步动态随机访问存储器，同步是指memory工作需要同步时钟，内部命令的发送与数据的传输都以它为基准；动态是指存储阵列需要不断地刷新以保证数据不丢失；随机访问是指数据不是线性依次读写，而是可以自由指定地址进行读/写。

SDRAM的内部有存储单元整列，给出行地址，列地址，就可以选择相应的存储单元，如下图中右侧部分所示。

![](/IMG/sdram_frame.png)

图上左侧的信号，对应于顶层文件的这些接口，有部分信号芯片手册上未标明如dq。 

```verilog
   output wire          sdr_clk_o,
   output wire          sdr_cs_n_o,
   output wire          sdr_cke_o,
   output wire          sdr_ras_n_o,
   output wire          sdr_cas_n_o,
   output wire          sdr_we_n_o,
   output wire [1:0]    sdr_dqm_o,
   output wire [1:0]    sdr_ba_o,
   output wire [11:0]   sdr_addr_o,
   inout  wire [15:0]   sdr_dq_io,
```

接口说明如下：

| 序号    | 接口名  | 宽度(bit) |   输入/输出 | 作用
| :----  | :------ | :----     |   :-----   | :--------------
| 1      | ADDR    | 12        |   输入      | 地址线
| 2      | CLK     | 1         |   输入      | 时钟
| 3      | CKE     | 1         |   输入      | 时钟使能
| 4      | RAS     | 1         |   输入      | 行地址选通，低有效
| 5      | CS      | 1         |   输入      | 片选，低有效
| 6      | CAS     | 1         |   输入      | 列地址选通，低有效
| 7      | WE      | 1         |   输入      | 写使能，低有效
| 8      | DQM     | 2         |   输入      | 字节选择和输出使能，低有效
| 9      | DQ      | 16        |   双向      | 数据线
| 10     | BA      | 2         |   输入      | bank选择

对于SDRAM更深刻的介绍，需要很大的篇幅，由于我们并非需要直接驱动SDRAM，而只需要驱动SDRAM的控制器，所以这里就不再展开，《自己动手写CPU》中关于Flash控制器有更多的描述。这里介绍的目的是，对SDRAM有一个基本的认识即可。

这个SDRAM控制器取自于OpenCores,该SDRAM控制器：
- 支持SDRAM的数据总线宽度可以为8,16,32
- 支持4个Bank的SDRAM
- 自动控制刷新
- 支持所有标准的SDRAm功能
- 支持 wishbone B总线

这是一个功能十分完善的控制器，根据说明，在实际使用过程中，**无需修改如何源码**我们只需配置如下参数就可以用了！


| 序号   | 参数名            | 宽度(bit) |   输入/输出 | 作用                                                                     |
| :-----| :--------------   | :-------  |  :-----    | :---------------------------------                                       |
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