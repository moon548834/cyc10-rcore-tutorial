# RISCV测例

对于测例来讲，我参考了部分zwp的工作，https://github.com/oscourse-tsinghua/undergraduate-zwpu2019 

同时也结合了最新的RISCV测例 https://github.com/riscv/riscv-tools

需要注意的是，zwp的工作中使用的第三方软核picrov32并**不能完善地支持特权级架构，并且有一些自定义的指令**，所以第一个链接中针对该CPU进行了一些特定的宏定义。然而我采用的CPU是比较完善的，所以对于zwp的工作需要进行适当修改。

## rv32ui指令

对于普通的用户级指令，我们是可以借鉴在picrov32中用到的方法，将所有的test_case一个一个测试。rv32ui测例位于 `./test/rv32ui` 下，直接make(默认的TARGET是rv32ui 或执行 `make TARGET=rv32ui` )即可生成相应的hex文件(并已经复制到quartus工程)，如果需要修改，需要注意的是以下几个位置：

- ./test/firmware/sections.ld     串口地址，ROM，RAM地址及大小
- ./test/firmware/start.S         可以通过注释修改进行的测例(此时需要删除 `/test/test`中的对应文件)
- ./test/rv32ui/riscv_test.h      串口地址，即代码中0x02000000的部分 

## rv32si指令与rv32mi指令

支持M和S态特权级架构的原始测例位于 `./riscv-test/isa/` ，由于每个指令的异常处理，状态并不相同，而且指令总共也不多，故我这里就没有将他们整合到一起，我目前的方法是将这些生成的指令拷贝到 `./test/rvmsi/` 中，然后回到test目录下，执行 `make TARGET=rv32mi-p-xxx` 。

>对于rv32si与rv32mi指令拷贝过来的就是elf格式的文件

所以这里完全是用的官方的文件，不过也进行了适当修改，如需修改则需要注意以下几个位置，原因同上。

- ./riscv-test/env/p/link.ld  
- ./riscv-test/env/p/riscv_test.h

## rv32ua指令

相比于基本的运算，跳转，访存指令，原子指令如果遇到问题，需要更多的背景知识才能更好地进行调试。这里根据相关手册，简单介绍一下测例中涉及到的指令。

> 由于本人对原子指令理解不是很深刻，可能下面两小节叙述有错误，若有不解留言或参考手册也可

### AMO指令

AMO指令对内存中的操作数执行一个原子操作，并将目标寄存器设置为操作前的内存值。原子表示内存读写之间的过程不会被打断，内存值也不会被其它处理器修改。

在手册中有这样一个例子，实现互斥：

```
    li t0, 1 # Initialize swap value.
again:
    amoswap.w.aq t1, t0, (a0) # Attempt to acquire lock.
    bnez t1, again # Retry if held.
# ...
# Critical section.
# ...
    amoswap.w.rl x0, x0, (a0) # Release lock by storing 0. 
```

首先初始化交换值，这里让t0等于1;然后执行amoswap操作，这条语句的意思原子地把内存memory[a0]的值先读取在t1中，将交换结果(即t0)重新保存到memory[a0]中，其中涉及到一次内存读与一次内存写，CPU保证读写之间不被打断。

> aq,rl对于单处理器来说不必考虑，这里的交换只会改变位于memory[a0]的值，和寄存器t1的值，t0不会改变

如果t1(也就是原先的memory[a0])不等于0，就会重新请求(等待其他线程释放资源)，否则就执行临界区代码。此时memory[a0]会置为1，等到最后一条语句的时候会释放。

### LR/SC指令

LR/SC指令保证了它们两条指令之间的操作的原子性。LR读取一个内存字，存入目标寄存器中，并留下这个字的保留记录。而如果SC的目标地址上存在保留记录，它就把字存入这个地址。如果存入成功，它向目标寄存器中写入0；否则写入一个非0的错误代码。

同样的，手册中也有一个例子，实现原子交换比较：

```
# a0 holds address of memory location
# a1 holds expected value
# a2 holds desired value
# a0 holds return value, 0 if successful, !0 otherwise
cas:
    lr.w t0, (a0) # Load original value.
    bne t0, a1, fail # Doesn’t match, so fail.
    sc.w t0, a2, (a0) # Try to update.
    bnez t0, cas # Retry if store-conditional failed.
    li a0, 0 # Set return to success.
    jr ra # Return.
fail:
    li a0, 1 # Set return to failure.
    jr ra # Return.
```

首先从memory[a0]中取出数据至t0，如果和预期的不符合那就直接到fail了，如果和预期的值a1相符，则继续执行 `sc.w `语句，尝试将a2写入到memory[a0]，并将结果保存至t0，对于本条SC指令来说，结果保存到t0，如果成功t0就是0，否则是一个非0的数；接下来语句 `bnez` 意思是如果t0不是0，也就是SC失败了，那么重新调到cas执行，否则就代表成功，可以返回了。

### rv32ua指令测试

rv32ua指令的测试方法与rv32ui类似，执行 `make TARGET=rv32ua` 即可

## 测例详解

由于测例都是通过宏来封装的，所以就有必要搞清楚这些宏的工作原理以便排查问题和增添测例。下面以 `addi.S` 为例进行一些说明

```C
#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN
```

打开 `addi.S` 文件后，看到在真正的测例宏前有如下几行，其中 `riscv_test` 包含了一些测试初始化，打印`PAST`，`FAIL`的宏，而 `test_macros.h` 则包含了不同指令测试的宏。，具体之后还会有例子。

下面 `RVTEST_RV32U` 代表这是32位的测例，因为 `riscv-test` 只有在64位下才有真正的源代码，32位只是借用了64位的测例，并通过宏的形式进行少量修改，因为要测试的是32位指令集，所以要有这个。

`RVTEST_CODE_BEGIN` 是来自于 `riscv_test.h` 

```C
#define RVTEST_CODE_BEGIN       \ 
    .text;              \
    .global TEST_FUNC_NAME;     \
    .global TEST_FUNC_RET;      \
TEST_FUNC_NAME:             \
    li  a0, 0x00ff;     \
.delay_pr:              \
    addi    a0,a0,-1;       \
    bne a0,zero,.delay_pr;  \
    lui a0,%hi(.test_name); \
    addi    a0,a0,%lo(.test_name);  \
    lui a2,0x02000000>>12;  \
.prname_next:               \
    lb  a1,0(a0);       \
    beq a1,zero,.prname_done;   \
    sw  a1,0(a2);       \
    addi    a0,a0,1;        \
    jal zero,.prname_next;  \
.test_name:             \
    .ascii TEST_FUNC_TXT;       \
    .byte 0x00;         \
    .balign 4, 0;           \
.prname_done:               \
    addi    a1,zero,'.';        \
    sw  a1,0(a2);       \
    sw  a1,0(a2);
```

`.delay_pr`是一个延时，原先可能是0xffff或者一个更大的数，但是在仿真下回消耗很大不必要的时间，这里我给调小了点，这部分是打印功能测试的名字，对于本例是`addi..`，之后就进入了真正的测例

```
  #-------------------------------------------------------------
  # Arithmetic tests
  #-------------------------------------------------------------

  TEST_IMM_OP( 2,  addi, 0x00000000, 0x00000000, 0x000 );
  TEST_IMM_OP( 3,  addi, 0x00000002, 0x00000001, 0x001 );
  TEST_IMM_OP( 4,  addi, 0x0000000a, 0x00000003, 0x007 );
```

`TEST_RP_OP` 是一个宏，这个宏的定义如下

```c
#define TEST_IMM_OP( testnum, inst, result, val1, imm ) \
    TEST_CASE( testnum, x3, result, \
      li  x1, val1; \
      inst x3, x1, SEXT_IMM(imm); \
    )
```


宏的声明不难理解，内容则是调用另一个宏TEST_CASE，其中SEXT_IMM(imm)是

```c
#define SEXT_IMM(x) ((x) | (-(((x) >> 11) & 1) << 11))
```

而TEST_CASE定义如下：

```c
#define TEST_CASE( testnum, testreg, correctval, code... ) \
test_ ## testnum: \
    code; \
    li  x29, correctval; \
    li  TESTNUM, testnum; \
    bne testreg, x29, fail;
```

追踪到TEST_CASE 一上来是一个声明第一个test，`test_ ## testnum` 将会被展开成 `test_1 test_2` 的形式, 之后code则是通过TEST_IMM_OP传进来的，这里是一个可变参量，所以可以有多条语句。之后将比对运算结果是否是正确的即 `testreg` 的数值是否和 `correctval` 相等，如果不相等就跳转到失败，打印"FAIL"然后返回。

将宏`TEST_IMM_OP`对于本例进行展开就是

```
li x1, 0x00000000,
addi x3, x1, SEXT_IMM(0)
li x29, 0
li TESTNUM, 2
bne x3, x29, fail
```

即验证`0 + 0 ?= 0` 