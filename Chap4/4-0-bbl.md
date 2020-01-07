# bbl启动流程分析 

Berkeley Boot Loader (BBL) 是 M 态的程序，可以引导我们移植的 BBL-uCore以及 linux等操作系统。其基本上可以认为是硬件/软件的接口，无论是对于操作
系统的移植，还是对于 RISC-V 的硬件设计，都是同等的重要的。下面简要介绍 BBL 所完成的功能。(以下工作部分参考了lkx的报告)

## step1

相关代码： 
- `./machine/mentry.S`
- `./machine/minit.c`

 在运行BBL之前，首先应将BBL置于内存0x8000_0000之后的位置，0x8000_0000处对应的时`./machine/mentry.S`中的一条跳转到do_reset指令。之后跳转到do_reset时首先进行的是寄存器清零，置mscratch为0。接下来将mtvec设置为trap_vector的地址，并进行检测。设置sp为binary最后的位置(页对齐)，跳转到 **init_first_hart** 。对应代码如下：

> 似乎markdown还不支持riscv汇编，所以目前只能没有高亮显示了

 ```
 do_reset:
  # 清空reg
  li x1, 0
  li x2, 0
  li x3, 0
  li x4, 0
  li x5, 0
  li x6, 0
  li x7, 0
  li x8, 0
  li x9, 0
  li x10, 0
  li x11, 0
  li x12, 0
  li x13, 0
  li x14, 0
  li x15, 0
  li x16, 0
  li x17, 0
  li x18, 0
  li x19, 0
  li x20, 0
  li x21, 0
  li x22, 0
  li x23, 0
  li x24, 0
  li x25, 0
  li x26, 0
  li x27, 0
  li x28, 0
  li x29, 0
  li x30, 0
  li x31, 0
  # 清空mscratch
  csrw mscratch, x0
  # 设置mtvec为trap_vector并检测
  la t0, trap_vector
  csrw mtvec, t0
  csrr t1, mtvec
1:bne t0, t1, 1b

  # 设置sp位整个binary末尾处，并且是页对齐的
  la sp, _end + 2*RISCV_PGSIZE - 1
  li t0, -RISCV_PGSIZE
  and sp, sp, t0
  addi sp, sp, -MENTRY_FRAME_SIZE

  csrr a0, mhartid
  slli a1, a0, RISCV_PGSHIFT
  add sp, sp, a1

  # 跳转到 init_first_hart
  beqz a0, init_first_hart

 ```

## step2

跳转到 **init_first_hart** 这个C语言函数后，进行了一些列初始化的工作，包括M态的一些csr设置，fp初始化，解析在地址0x00001000处的config_string，初始化中断，初始化内存单元，及以上相关操作的检测，最后是加载OS，具体函数位于 
- `./machine/minit,c`
- `./machine/

```c
void init_first_hart()
{
  hart_init();
  hls_init(0); // this might get called again from parse_config_string
  parse_config_string();
  plic_init();
  hart_plic_init();
  prci_test();  
  unaligned_r_w_test();
  memory_init();
  memory_check();
  boot_loader();
}
```

> 由于代码较多故以总结的形式列举如下，详细请参考源码

在 **hart_init** 中，主要涉及几个函数 `mstatus_init`， `fp_init`， `delegate_traps`

**mstatus_init** ：
```
// 设置页表映射模式
mstatus.VM = VM32
mstatus.FS= 1
// 使能S态和U态的性能检测(似乎没啥用)
mucounteren = -1
mscounteren = -1
// 禁止时钟中断，允许其他类型的中断
mie = ~MIP_MTIP
```

**fp_init**:
```
//清空misa中关于'F'与'D'的描述
misa.'F' = 0;
misa.'D' = 0;
```

> misa是一个反映这个处理器支持那些ISA的一个M态的csr

>> 'F'的定义是 单精度的浮点拓展

>> 'D'的定义是 双精度的浮点拓展

> 关于更多的资料请查阅riscv特权级手册中的描述(但个人感觉此处并非很重要，知道设置为0就可以了)

**delegate_traps**:
```
// 将S太的中断和大多数的异常都传递给S态处理 
mideleg = MIP_SSIP | MIP_STIP | MIP_SEIP
medeleg = (1U << CAUSE_MISALIGNED_FETCH) |
          (1U << CAUSE_FAULT_FETCH) |
          (1U << CAUSE_BREAKPOINT) |
          (1U << CAUSE_FAULT_LOAD) |
          (1U << CAUSE_FAULT_STORE) |
          (1U << CAUSE_BREAKPOINT) |
          (1U << CAUSE_USER_ECALL);
```

此后进入到 **hls_init** ，但由于这个函数会被parse_config再调用一次，所以等之后一起分析，

**parse_config_string**: 这个函数的主要功能就是读取位于0x0000_1000中的一些config然后软件进行相应的设置，为了节省启动时间与fpga的空间，我对此部分进行了一定优化，具体说来就是在bbl写死这些config的值，而不是从硬件上去读取。因为无论如何总归要在硬件上或者软件上指定这些参数(SDRAM的起始位置，大小，UART地址等)，所以个人认为从软件上写死不仅可以节省查询config的时间，而且也节省了fpga的资源，也加快了仿真的进度。

代码位于：
- 

> 我使用的板子逻辑资源只有15.5k，当我综合这个SOC的时候，已经用了15k(98%).. 这还是在进行了一些优化的情况下 所以能省则省..

举个例子来讲，对于 `query_mem` 这个函数而言，他希望获取的是ram的地址和大小，所以我们通过注释掉query_config_string相关操作，就可以不必从硬件上获取，而是直接幅值即可，其余的query函数以此类推。

```c
static void query_mem(const char* config_string)
{
  //query_result res = query_config_string(config_string, "ram{0{addr");
  //assert(res.start);
  //uintptr_t base = get_uint(res);
  uintptr_t base = (uintptr_t)0x80000000;
  assert(base == DRAM_BASE);
  //res = query_config_string(config_string, "ram{0{size");
  //mem_size = get_uint(res);
  mem_size = (uint64_t)0x00400000;
}
```

**hart_plic_init**： 主要目的是清除中断

```c  
*HLS()->ipi = 0;
*HLS()->timecmp = -1ULL;
write_csr(mip, 0);
```

**memory_init**： 计算mem_size和第一个未被占用的物理地址

```c
mem_size = mem_size / MEGAPAGE_SIZE * MEGAPAGE_SIZE;
first_free_paddr = sbi_top_paddr() + num_harts * RISCV_PGSIZE;
```
## step3 boot_loader

进行完以上的初始化任务后，进入到boot_loader函数中，首先打印loading OS的字符串，接下来进入load_kernel_elf这个函数加载elf格式的OS，然后是S态支持虚拟内存的一些初始化过程，接下来打印logo，刷tlb，最终进入到S态的OS中，至此所有的bootloader工作全部结束，控制权交给OS kernel。

代码位于 .
- ./bbl/bbl.c 
- ./bbl/kernel_elf.c
- ./bbl/elf.h

```c
log("machine mode: loading payload OS...");
extern char _payload_start, _payload_end;
load_kernel_elf(&_payload_start, &_payload_end - &_payload_start, &info);
supervisor_vm_init();
print_logo();
mb();                                                                                                                                     
elf_loaded = 1;
enter_supervisor_mode((void *)info.entry, 0);
```

**load_kernel_elf**: 加载os

这里简单介绍elf文件，不是重点，在 `./bbl/elf.h` 文件中，elf文件格式定义如下：

```c
typedef struct {
  uint8_t  e_ident[16];
  uint16_t e_type;
  uint16_t e_machine;
  uint32_t e_version;
  uint32_t e_entry;
  uint32_t e_phoff;
  uint32_t e_shoff;
  uint32_t e_flags;
  uint16_t e_ehsize;
  uint16_t e_phentsize;
  uint16_t e_phnum;
  uint16_t e_shentsize;
  uint16_t e_shnum;
  uint16_t e_shstrndx;
} Elf32_Ehdr;
```

一开始的几个结构从`e_ident`到`e_version`都是存储的关于文件格式信息，在`load_kernel_elf`这个函数开始进行了相关检查，包含头格式，物理地址大小等。由于最终采取的是4KB映射，所以此时修改了第一个空闲物理地址的起始位置时页对齐，而不是巨页对齐。

```c
first_free_paddr = ROUNDUP(first_free_paddr, RISCV_PGSIZE);
```
之后函数通过检测所有的加载段，来获取最小的虚拟地址。然后进行段的复制(从物理地址到虚拟地址的位置，实际上应该是从物理地址A到虚拟地址所映射的物理地址B的复制，**不过此时还没映射，但可以看作是上面那句话**)，这样设置完页表就可以进入到`e_entry`执行程序了。所以执行程序之前还需要进行一些M态的设置，

**superviosr_vm_init**:页表设置
这也就是`supervisor_vm_init`函数的工作，最关键的是设置页表的映射，另外需要注意的是最后需要把sbi映射到虚地址的最顶端部分。在看源码结合lxs工作的同时，我注意到

```c
for (size_t i = 0; i < num_middle_pts - 1; i++)
    root_pt[(1<<RISCV_PGLEVEL_BITS)-num_middle_pts+i] = ptd_create(((uintptr_t)middle_pt >> RISCV_PGSHIFT) + i);
```

这部分的 `num_middle_pts - 1` 就是把最后的位置空给sbi(我的理解是这样)。另外在仿真环境下，由于速度不是很快，所以如果os的虚拟地址从0xc0004000开始的话，因为如下语句：

```c
size_t num_middle_pts = (-info.first_user_vaddr - 1) / MEGAPAGE_SIZE + 1;
pte_t* root_pt = (void*)middle_pt + num_middle_pts * RISCV_PGSIZE;
memset(middle_pt, 0, (num_middle_pts + 1) * RISCV_PGSIZE);
```

会导致初始化非常大的空间，但其实没有必要，因为os用不到那么多，所以我这里把os的虚起始地址设置为0xfc40_0000，目的是减小`num_middle_pts`，加快仿真。

> 这部分都是一些页表的操作，还是建议理解清楚

在函数最后刷新`sptbr`也就是`satp`,之后便进入到S态的os中了。