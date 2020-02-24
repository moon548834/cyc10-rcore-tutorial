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
- ./machine/minit
- ./machine/

> 实际上这个config_string我为了降低仿真时间，大部分都直接在软件写死了。

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
// 将S态的中断和大多数的异常都给S态处理 
mideleg = MIP_SSIP | MIP_STIP | MIP_SEIP
medeleg = (1U << CAUSE_MISALIGNED_FETCH) |
          // (1U << CAUSE_FAULT_FETCH) |
          (1U << CAUSE_BREAKPOINT) |
          // (1U << CAUSE_FAULT_LOAD) |
          // (1U << CAUSE_FAULT_STORE) |
          (1U << CAUSE_BREAKPOINT) |
          (1U << CAUSE_USER_ECALL);
```

> 需要注意的是，对于**有些异常，还是交由M态处理**的(就是那些mideleg和medeleg没有置0的位对应的异常中断)，因为实际上这个cpu的页表替换功能不是很健全，需要软件的协助，这部分的软件实际上位于bbl，也就是说当发生某些异常如page_fault的时候，操作系统会维护一些部分，bbl也会维护一些部分，硬件做的是只是读/写对应的tlb表项，而硬件并不会自主替换哪个页表(比如替换算法就是bbl来维护的)，这一点与原来的bbl不一样需要特别留意，否则无法理解整个系统的运作。

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

一开始的几个结构从`e_ident`到`e_version`都是存储的关于文件格式信息，在`load_kernel_elf`这个函数开始进行了相关检查，包含头格式，物理地址大小等。(如果最终采取的是4KB映射，所以此时修改了第一个空闲物理地址的起始位置时页对齐，而不是巨页对齐。)

```c
first_free_paddr = ROUNDUP(first_free_paddr, RISCV_PGSIZE);
```

之后函数通过检测所有的加载段，来获取最小的虚拟地址。然后进行段的复制(从物理地址到虚拟地址的位置，实际上应该是从物理地址A到虚拟地址所映射的物理地址B的复制，**不过此时还没映射，但可以看作是上面那句话**)，这样设置完页表就可以进入到`e_entry`执行程序了。所以执行程序之前还需要进行一些M态的设置，

**superviosr_vm_init**:页表设置
这也就是`supervisor_vm_init`函数的工作，最关键的是设置页表的映射，另外需要注意的是最后需要把sbi映射到虚地址的最顶端部分。

```
  uintptr_t num_sbi_pages = ((uintptr_t)&_sbi_end - DRAM_BASE - 1) / RISCV_PGSIZE + 1;
  assert(num_sbi_pages <= (1 << RISCV_PGLEVEL_BITS));
  for (uintptr_t i = 0; i < num_sbi_pages; i++) { //sbi可能有很多页(二级)
    uintptr_t idx = (1 << RISCV_PGLEVEL_BITS) - num_sbi_pages + i;
    sbi_pt[idx] = pte_create((DRAM_BASE / RISCV_PGSIZE) + i, PTE_G | PTE_R | PTE_X);
  }
  pte_t* sbi_pte = middle_pt + ((num_middle_pts << RISCV_PGLEVEL_BITS) - 1); //middle_pt = root_pt
  *sbi_pte = ptd_create((uintptr_t)sbi_pt >> RISCV_PGSHIFT); //最终映射sbi_pt到root_pt上
```

> 这部分都是一些页表的操作，还是建议通过阅读源码理解清楚(Ps: 实际上这里不映射也行的，因为ecall也是交由M态处理了qaq)

在函数最后刷新`sptbr`也就是`satp`,之后便进入到S态的os中了。

# bbl对TLB的支持实现

仅仅是了解了启动流程还是不够的，我们需要关注一些软硬件配合的细节，这里需要强调一点是由于硬件并没有完全控制tlb的过程，所以实际上是由软件维护tlb的，比如tlb满的时候究竟要换哪个页。这个tlb表项要写入的数值是什么等等。

首先我们来看 `./machine/mentry.S`这个文件，

```
trap_table:
  .word bad_trap
  .word tlb_i_miss_trap
  .word illegal_insn_trap
  .word bad_trap
  .word misaligned_load_trap
  .word tlb_r_miss_trap
  .word misaligned_store_trap
  .word tlb_w_miss_trap
```

代码一开始就是一个`trap_table`里面储存着各个trap的处理程序，举个例子，对于`tlb_i_miss_trap`而言,他对应的函数位于`./machine/emulation.c`中:
```
void tlb_i_miss_trap(uintptr_t* regs, uintptr_t mcause, uintptr_t mepc)
{
  tlb_miss_trap(regs, mcause, mepc, 1, 0, 0);
}
```

我们目前先不关心这个函数究竟干什么了，只需要知道这个`trap_table`是存储的各种trap的处理程序的地址就可以。由于这些trap都是在m态被触发的，结合RISCV的架构，我们知道有一个`mtvec`的寄存器十分关键，在处理器m态下发生异常时，硬件会根据mtvec跳转到相应的地址，那么在bbl中mtvec被设置成什么了呢？实际上就在`./machine/mentry.S`中

```
  la t0, trap_vector
  csrw mtvec, t0
```

这里我们看到，bbl把trap_vector赋值给了mtvec,而trap_vector也在这个文件中，对应代码如下:

```
trap_vector:
  csrrw sp, mscratch, sp
  beqz sp, .Ltrap_from_machine_mode # 这里也是最终跳转到.Lhandle_trap_in_machine_mode中的

  STORE a0, 10*REGBYTES(sp)
  STORE a1, 11*REGBYTES(sp)

  csrr a1, mcause
  bgez a1, .Lhandle_trap_in_machine_mode

  # This is an interrupt.  Discard the mcause MSB and decode the rest.
  sll a1, a1, 1

  # Is it a machine timer interrupt?
  li a0, IRQ_M_TIMER * 2
  bne a0, a1, 1f
  li a1, TIMER_INTERRUPT_VECTOR
  j .Lhandle_trap_in_machine_mode
  
```
这里我们看到根据中断异常不同的类型，最终都会跳转到 .Lhandle_trap_in_machine_mode中

```
.Lhandle_trap_in_machine_mode:
  # Preserve the registers.  Compute the address of the trap handler.
  STORE ra, 1*REGBYTES(sp)
  STORE gp, 3*REGBYTES(sp)
  STORE tp, 4*REGBYTES(sp)
  STORE t0, 5*REGBYTES(sp)
1:auipc t0, %pcrel_hi(trap_table)  # t0 <- %hi(trap_table) 
  STORE t1, 6*REGBYTES(sp)
  sll t1, a1, 2                    # t1 <- mcause << 2
  STORE t2, 7*REGBYTES(sp)
  add t1, t0, t1                   # t1 <- %hi(trap_table)[mcause]
  STORE s0, 8*REGBYTES(sp)
  LWU t1, %pcrel_lo(1b)(t1)         # t1 <- trap_table[mcause] #GOT表 indirect addressing
  STORE s1, 9*REGBYTES(sp)
  mv a0, sp                        # a0 <- regs
  STORE a2,12*REGBYTES(sp)
  csrr a2, mepc                    # a2 <- mepc
  STORE a3,13*REGBYTES(sp)
  csrrw t0, mscratch, x0           # t0 <- user sp
  STORE a4,14*REGBYTES(sp)
  # more store ...
  jalr t1 # 跳转到t1对应的地址
  # restore ...
```

可以看到根据mcause选择相应的trap_table的偏移量(即对应哪个trap处理程序),t1最终就指向了对应的处理程序的地址，最终一个jalr就跳转过去了。

现在我们就大致搞清了，当发生一个trap的时候，究竟bbl哪部分在起作用，整个流程是如何的。当我们的操作系统在S态发生一个tlb_i_miss的时候，会出现一个strap，着个strap由于medeleg的设置对应位是0，所以交给了M态处理，处理的函数就是trap_vector，根据mcause里面对应的trap，软件会知道这个是一个tlb_i_miss，进行一些跳转前的保护寄存器的工作后，就跳转到这个trap_table里面对应的tlb_i_miss的地址上去执行了，执行完毕后，就恢复寄存器最后执行mret就可以了。

下一步我们来看看究竟tlb_i_miss中间bbl干了什么(这部分是原来bbl没有的，大部分程序都是由lkx添加的)

## tlb_miss_trap

首先无论是指令缺失还是数据缺失最终都会引到`tlb_miss_trap`中,只不过属性值不太一样而已:

```
void tlb_i_miss_trap(uintptr_t* regs, uintptr_t mcause, uintptr_t mepc)
{
  tlb_miss_trap(regs, mcause, mepc, 1, 0, 0);
}
void tlb_r_miss_trap(uintptr_t* regs, uintptr_t mcause, uintptr_t mepc)
{
  tlb_miss_trap(regs, mcause, mepc, 0, 1, 0);
}
void tlb_w_miss_trap(uintptr_t* regs, uintptr_t mcause, uintptr_t mepc)
{
  tlb_miss_trap(regs, mcause, mepc, 0, 0, 1);
}
```

这个函数`tlb_miss_trap`是控制tlb的核心,我们首先看下这个函数的原型:
`void tlb_miss_trap(uintptr_t* regs, uintptr_t mcause, uintptr_t mepc, int ex, int rd, int wt)`

还是比较好顾名思义的，所谓regs，就是寄存器的地址, mcause, mepc就是csr中的数值，不过需要注意的是，这里的regs, mcause都已经被**实实在在地存储在内存中某个地方**，而不是硬件中地某个LUT,FF，这点需要搞清楚。

一个自然的问题是他们是怎么完成硬件到内存这样一个过程呢，其实就是在刚刚地`.Lhandle_trap_in_machine_mode:`完成了，我们再来回头看一下:

```
...
csrr a1, mcause
...
STORE s1, 9*REGBYTES(sp)
mv a0, sp                        # a0 <- regs
STORE a2,12*REGBYTES(sp)
csrr a2, mepc                    # a2 <- mepc
...
```

实际上regs(所对应的堆栈sp)和mcause, mepc已经被保存到 a0, a1, a2上了，根据cdecl调用规则和riscv的寄存器调用规则我们就可以知道，当调用这个tlb_miss_trap函数的时候，a2, a1, a1(从右到左)会被依次压栈，然后`tlb_miss_trap`进入这个函数的时候就会依次pop出来使用了。

> 这部分可以更多看看手册，有大致概念就可以

好了我们正式看这个tlb_miss_trap函数了:
首先获取 mstatus中vm的数值以方便知道是用的RV_32页表还是其他的，然后根据__riscv_xlen的数值,判断是32位还是64位的系统，从而获取相应的页表基地址。这部分代码如下:

```

  uintptr_t mstatus = read_csr(mstatus);
  uint32_t vm = (EXTRACT_FIELD(mstatus, MSTATUS_VM));

#if __riscv_xlen == 32
  uint32_t p = 32;
  uintptr_t a = ((read_csr(sptbr)) & ((1 << 22) - 1)) * RISCV_PGSIZE;
#else
  uint32_t p = 64;
  uintptr_t a = ((read_csr(sptbr)) & ((1ll << 38) - 1)) * RISCV_PGSIZE;
#endif

  switch(vm)
  {
    case VM_SV32: levels = 2; ptesize = 4; vpnlen = 10; break;
    case VM_SV39: levels = 3; ptesize = 8; vpnlen = 9; break;
    case VM_SV48: levels = 4; ptesize = 8; vpnlen = 9; break;
    default: die("unsupport mstatus.vm = %x", vm);
  }
```

我们这里是VM32，lever2意思是两级页表，ptesize是每个页表的字节数，对于32位os是4字节，vpn长度是10。这里如果对riscv页表不太熟悉可以看看 https://learningos.github.io/rcore_step_by_step_webdoc/docs/%E9%A1%B5%E8%A1%A8%E7%AE%80%E4%BB%8B.html 或者是riscv中文手册

```
    for (i = levels - 1; ; i --) {
      p -= vpnlen;  // p = 32 - 10 = 22
      // 之前mask = 0
      mask = ~((~mask) >> vpnlen); //这行之后mask = 1111_1111_1000_00...._0000
      uintptr_t vpn = ((va >> p) & ((1 << vpnlen) - 1)); //vpn = va[31:22]
      uintptr_t *pte_p = (uintptr_t *)(a + vpn * ptesize); // a = root_page_table pte 相当于是root的偏移量
      uintptr_t pte = *pte_p;
```

当第一次进入这个循环的时候, a就是上文中对应的root_page_table 找到的pte, 而pte_p就代表这个虚拟地址对应的一级页表的地址，然后pte就是一级页表(或者叫巨页)，页目录项的值了。

进行一些检查之后，如果当前页表的内容是指向下一级的(X W R均为0)，那么更新a位当前pte对应的页表项基址:

```
 if ((pte & (PTE_X | PTE_W | PTE_R)) == 0)
    {
      a = (pte >> 10) << RISCV_PGSHIFT;
    }
```

好了接下来涉及到一些硬件自定义的csr寄存器，这里需要结合着verilog代码来看:

涉及到的寄存器主要及功能如下表：

CSR寄存器数值 | 对应硬件宏       | 含义
------------ | ----------       | ------
0x7c0        | CSR_mtlbindex    |
0x7c1        | CSR_mtlbvpn      |
0x7c2        | CSR_mtlbmask     |
0x7c3        | CSR_mtlbpte      |
0x7c4        | CSR_mtlbptevaddr |









