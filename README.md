## redis-tools

2024-09-20

有下面几个目录：

### examples

包含简单的 hiredis 测试程序。用于连接 redis 集群，测试命令。

进入目录执行 make 即可。然后执行 rediscmd。请更改代码中的 ip，port，authpass 符合你的测试环境。

### libs

包含了编译好的 hiredis 库和头文件。

### redis

包含了全部 redis 集群创建脚本。使用请参考 README.md。

### sslcerts

如何使用 openssl 创建证书。

java web 服务器请使用 jkscerts.sh 自动化工具创建证书库和证书！
