# RISCV测例

对于测例来讲，我参考了部分zwp的工作，https://github.com/oscourse-tsinghua/undergraduate-zwpu2019 

同时也结合了最新的RISCV测例 https://github.com/riscv/riscv-tools

需要注意的是，zwp的工作中使用的第三方软核picrov32并**不能完善地支持特权级架构，并且有一些自定义的指令**，所以第一个连接中针对该CPU进行了一些宏定义。然而我采用的CPU是比较完善的，所以对于zwp的工作需要进行适当修改。

## rv32ui指令

对于普通的用户级指令，我们是可以借鉴在picrov32中用到的方法，将所有的test_case一个一个测试。rv32ui测例位于 `/test/rv32ui` 下，直接make(默认的TARGET是rv32ui 或执行 `make TARGET=rv32ui`)即可生成相应的hex文件(并已经复制到quartus工程)，如果需要修改，需要注意的是以下几个位置：

- /test/firmware/sections.ld   串口地址，ROM，RAM地址及大小
- /test/firmware/start.S       可以通过注释修改进行的测例(此时需要删除 `/test/test`中的对应文件)
- /test/test/riscv_test.h      串口地址，即代码中0x02000000的部分 

仿真效果图如下：

![](/IMG/rv32ui_sim.png)


下板效果图如下：

![](/IMG/rv32ui_board.png)

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

rv32ua指令的测试方法与rv32ui类似，执行`make TARGET=rv32ua`即可 ，最终结果如下：

仿真效果图如下：

![](/IMG/rv32ua_sim.png)


下板效果图如下：

![](/IMG/rv32ua_board.png)