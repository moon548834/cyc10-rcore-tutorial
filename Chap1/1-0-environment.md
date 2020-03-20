# 一些环境搭建说明

本工程在windows10操作系统下进行，涉及到的软件如 Quartus 18.0(prime), modelsim 等均在windows下使用

> modelsim在Quartus安装的时候可以勾选一并安装

对于其中涉及到linux的相关操作，全部在WSL(linux子系统ubuntu16.04进行)，当然也可以使用虚拟机操作，不过这样速度会慢一些。需要注意的是WSL默认挂载在C盘，如果C盘空间不足，请更改挂载位置，由于本人只有C盘是固态，所以按照默认方式进行。

> 在WLS下可以通过 `cd /mnt/c/...`的方式，迅速的切换到C盘目录(其他盘类推)，之后便可以用命令行的形式在windows下工作，由于本人比较熟悉命令行与vim，所以经常使用此方法。

## RISCV交叉编译链

### 安装命令
    $ sudo apt-get install autoconf automake autotools-dev curl libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev libexpat-dev
    $ git clone --recursive https://github.com/riscv/riscv-gnu-toolchain
    $ cd riscv-gnu-toolchain
    $ ./configure --prefix=/opt/riscv --with-arch=rv32ima --with-abi=ilp32
    $ make -j4

> arch中的a参数代表原子指令，对于跑操作系统来讲是不可或缺的，另外由于我选用的cpu没有fpu硬件，所以采用ilp32软浮点模拟的功能

> 由于编译链比较大，且可能会访问一些google源，所以请确保网络通畅，整个 `git clone update` 过程大约需要持续数小时，编译也是需要数小时，请耐心等待

更详细的参数请参考 https://github.com/riscv/riscv-gnu-toolchain 的说明

## 添加环境变量

在 `~/.bashrc`中添加 `PATH=/opt/riscv/bin:$PATH` 之后键入

    $ source ~/.bashrc

接下来在任何一个地方命令行输入 riscv32 后输入两次 Tab, 应该会有自动补全成 **riscv32-unknown-elf-** 并显示若干编译链工具，至此编译链安装成功。

如果安装了qemu，可以交叉一个riscv32格式的helloworld，并用qemu-riscv32运行之，用以简单的测试。

## 运行本工程以及分支介绍

好了，这个时候假定你已经正确地安装好了编译链，下面开始在modelsim下仿真本项目:

> 由于网速原因，有的时候会很慢，所以可以 git clone -b xxx -depth=1 指定分支clone，一般一个分支不会大于100MB (TODO 整理github减少一些不必要的文件)

```
git clone git@github.com:oscourse-tsinghua/undergraduate-fzpeng2020.git
git checkout feature-4MB-bbl-without-compression
./build.sh
```

> 注意涉及OS部分操作目前仅支持在仿真环境下运行

好了，接下来打开quartus,由于每个人的modelsim路径不一样，第一次需要设置modelsim的路径 `Tools->Options->General->EDA Tool Options`下设置相应的路径:

![](/IMG/quartus.PNG)

> 需要注意的是quartus和modelsim的关联设置，这里默认的是modelsim-altera，如是SE版本请自行在Assignments->Setting->EDA TOOL Settings->Simulation->Tool Name下选择合适的仿真版本。 如果改成SE版本需要在 `Assignments->Settings->EDA Tool Settings`下更改Tool Name

然后点击`Tool->Run Simulation Tool->RTL Simualtion` 不出问题的话，就应该可以自动跳转到modelsim仿真界面了。

**说明： 一般分支下有两个quartus project分别叫wishbone_cyc10, wishbone_cyc10_os,前者测指令，后者测OS**

### 分支: feature-4MB-bbl-without-compression

这个分支对应于仿真环境下(modelsim)可以跑操作系统,只需看**wishbone_cyc10_os**这个工程即可。对于这个分支而言需要先运行`build.sh`这样就可以正常仿真了。

### 分支：master

这个分支下只需要考虑工程**wishbone_cyc10**即可, 用的是第三方SDRAM IP核，可以下板(SDRAM有8MB,但实际上只有部分空间可以使用)。

### 分支: sdram_qsys

这个分支下只需考虑工程**wishbone_cyc10**即可，用的是quartus自带的IP核(和master的不一样), sdram仍有bug。

### 分支: sdram_naked

无CPU，只是用来测试SDRAM的，里面有一个可以认为是信号发生器的master，逻辑简单，可以用来验证SDRAM(虽然bug未解决)。

