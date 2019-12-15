# RISCV测例

对于测例来讲，我参考了部分zwp的工作，https://github.com/oscourse-tsinghua/undergraduate-zwpu2019 

同时也结合了最新的RISCV测例 https://github.com/riscv/riscv-tools

需要注意的是，zwp的工作中使用的第三方软核picrov32并**不能完善地支持特权级架构，并且有一些自定义的指令**，所以第一个连接中针对该CPU进行了一些宏定义。然而我采用的CPU是比较完善的，所以对于zwp的工作需要进行适当修改。

## rv32ui指令

对于普通的用户级指令，我们是可以借鉴在picrov32中用到的方法，将所有的test_case一个一个测试。所有的测例位于 `/test/test` 下，直接make即可生成相应的hex文件，如果需要修改，需要注意的是以下几个位置：

- /test/firmware/sections.ld   串口地址，ROM，RAM地址及大小
- /test/firmware/start.S       可以通过注释修改进行的测例(此时需要删除 `/test/test`中的对应文件)
- /test/test/riscv_test.h      串口地址，即代码中0x02000000的部分 

仿真效果图如下：

![](/IMG/RV32I_sim.png)


下板效果图如下：

![](/IMG/RV32I_board.png)
