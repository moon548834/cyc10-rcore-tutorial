# 一些环境搭建说明

本工程在windows10操作系统下进行，涉及到的软件如 Quartus 18.0(prime), modelsim 等均在windows下使用

> modelsim在Quartus安装的时候可以勾选一并安装

对于其中涉及到linux的相关操作，全部在WLS(linux子系统ubuntu16.04进行)，当然也可以使用虚拟机操作，不过这样速度会慢一些。需要注意的是WLS默认挂载在C盘，如果C盘空间不足，请更改挂载位置，由于本人只有C盘是固态，所以按照默认方式进行。

> 在WLS下可以通过 `cd /mnt/c/...`的方式，迅速的切换到C盘目录(其他盘类推)，之后便可以用命令行的形式在windows下工作，由于本人比较熟悉命令行与vim，所以经常使用此方法。

关于quartus和modelsim的软件安装按照提示步骤来就可以，关于riscv相关tools的安装见下一节。
