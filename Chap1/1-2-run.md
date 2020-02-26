# 运行本工程(modelsim)
好了，这个时候假定你已经正确地安装好了编译链，下面开始在modelsim下仿真本项目:

```
git clone git@github.com:oscourse-tsinghua/undergraduate-fzpeng2020.git
git checkout feature-4MB-bbl-without-compression
./build.sh
```

好了，接下来打开quartus,由于每个人的modelsim路径不一样，第一次需要设置modelsim的路径 `Tools->Options->General->EDA Tool Options`下设置相应的路径:

![](/IMG/quartus.PNG)

> 需要注意的是quartus和modelsim的关联设置，这里默认的是modelsim-altera，如是SE版本请自行在Assignments->Setting->EDA TOOL Settings->Simulation->Tool Name下选择合适的仿真版本。 如果改成SE版本需要在 `Assignments->Settings->EDA Tool Settings`下更改Tool Name

然后点击`Tool->Run Simulation Tool->RTL Simualtion` 不出问题的话，就应该可以自动跳转到modelsim仿真界面了。

