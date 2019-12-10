# RISCV交叉编译链
## 安装命令
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

# RISCV测例

对于测例来讲，我参考了部分zwp的工作，https://github.com/oscourse-tsinghua/undergraduate-zwpu2019 

同时也结合了最新的RISCV测例 https://github.com/riscv/riscv-tools

需要注意的是，zwp的工作中使用的第三方软核picrov32并**不能完善地支持特权级架构，并且有一些自定义的指令**，所以第一个连接中针对该CPU进行了一些宏定义。然而我采用的CPU是比较完善的，所以对于zwp的工作需要进行适当修改。


