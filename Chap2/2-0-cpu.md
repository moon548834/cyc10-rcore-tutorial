# CPU与SOC简单介绍

这个cpu采用的是lkx的工作 http://os.cs.tsinghua.edu.cn/oscourse/OS2017spring/projects/u1

该cpu是经典的5级流水线架构，支持m态和s态特权级，并且具有mmu单元与tlb，无cache设计。

soc则基于《自己动手写CPU》(雷思磊)结构，采用的是wishbone总线，其中sdram使用的是开源代码，uart自己重写(为了节省资源，只支持发送功能，且只有一个端口，波特率写死，无ready位)，片外flash目前尚不清楚如何工作，故采用片内rom，使用intel的.hex文件进行例化。总线交互也采用的是开源代码。
