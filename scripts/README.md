## redis-tools


Copyright (c) 2024-2030 maparare.top, All Rights Reserved.


**免责声明：使用本项目脚本给您造成的任何后果，本作者都不负任何责任。强烈建议您在虚拟机上执行本项目脚本。**

redis 集群安装管理shell脚本。仅仅支持 Linux CentOS 7，其他未测试。所有命令都是以 root 用户执行，因此 $ 后面全部省略 sudo。

redis 集群是指多个 redis-server 实例（服务进程）运行一台或多台服务器上，全部 redis-server 服务实例构成一个集群（通过创建脚本：create_cluster.sh）。

每个 redis-server 实例都要占用一个通讯端口（port），并且使用独有的配置文件启动。为保证高可用，一般选择至少 3 台服务器，每台机器 3 个实例的模式（复制数 redis_cluster_replicas=2）。

### 服务器准备工作

- 1) 要求安装 redis 集群的每个节点服务器能联网，能使用 yum install 更新软件，有 gcc 等编译工具链。

- 2) 每台服务器都要执行下面的命令安装特定依赖

        $ yum install openssl-devel zip unzip

- 3) 安装 jemalloc 开发库（jemalloc 在本项目的 "scripts/downloads" 目录下）

        $ cd jemalloc-5.2.1
        
        $ ./autogen.sh
         --with-jemalloc-prefix=je_ --prefix=/usr/local
        
        $ make && make install

    **注**：你可以仅仅在一台服务器上安装编译构建环境，然后复制构建的结果到其他服务器。（不推荐！）

- 4) 服务器时钟同步

    以下要求每个节点服务器都要执行！

    - 设置时区
    
            $ unlink /etc/localtime
            $ ln -s ../usr/share/zoneinfo/Asia/Shanghai /etc/localtime
            $ timedatectl

    - 设置时间

            $ date -s "2024-09-18 11:51:00"
            $ echo $(date +"%Y-%m-%d %H:%M:%S") | hwclock -w
            $ hwclock

    **注**：你可能需要设置时钟服务以确保服务器时钟保持一致！（不在本文讨论范围内）

### 创建 redis 集群

- 伪分布式

 在一台服务器上运行至少 9 个实例（9个不同端口）。
 
- 真分布式

 在至少 3 台服务器上，每个机器运行至少3个实例。本文以 3 个服务器，每个服务器运行 3 个实例为例。进入 scripts 目录，执行下面的命令：

        $ redis_cluster_install.sh redis-cluster.settings build config deploy

        命令第一个参数必须指定配置文件，后面的参数是要执行的动作。上面的命令等价于：

        $ redis_cluster_install.sh redis-cluster.settings ALL

    这样一个名为 test 的 redis 集群就创建好了，默认的位置在：

        /opt/redis_cluster/test


**在每台服务器都运行上面的脚本，以保证每个节点的集群安装正确**

### 启动 redis 集群

- 1) 分别在每个服务器都启动 redis 实例：

        $ /opt/redis_cluster/test/start_redis.sh

- 2) 当全部实例启动完成，在任意一台服务器上执行创建集群命令：

        $ /opt/redis_cluster/test/create_cluster.sh

- 3) 连接集群，执行下面的命令测试 redis 命令行：

        [root@hacl-node3 ~]# /opt/redis_cluster/test/connect_redis.sh
        Warning: Using a password with '-a' or '-u' option on the command line interface may not be safe.
        hacl-node3:6377> set name light
        -> Redirected to slot [5798] located at 10.0.2.5:6377
        OK
        10.0.2.5:6377> get name
        "light"
        10.0.2.5:6377>

### 配置集群

- 配置文件 redis-cluster.settings

    redis_cluster_install.sh 需要这个配置文件作为执行的第一个参数。你可以复制一个，然后根据需要更改其配置内容。


- redis 集群配置目录 conf.$redis_cluster_id

    **$redis_cluster_id 就是 redis-cluster.settings 里指定的 redis_cluster_id 名称。名称必须是规范的小写英文单词，不要与系统目录、命令、关键字等重名。脚本不对这个名称做任何检查，因此不正确的名称可能导致严重后果！**
    
    **以下是合法的名称示例：**
    
        test test123 devel myredis mapaware
    
    **以下是不合法的名称示例：**

        default usr bin chmod linux redis root

    配置目录包含的固定文件名：

    - cluster_nodes.ini
    
    配置了集群全部的节点。你可以更改它们以适合自己的配置。其中 conf="redis_server.conf0" 指向了 redis-server 服务实例使用的配置文件模板。你可用增加或更改模板内容以适合自己的配置需求。
    
    不推荐：你可以指定每个节点使用各自的配置模板（例如 conf="redis_server.conf.myself"）。

    - redis_server.conf0
    
    redis-server 服务实例使用的配置文件模板，用于实际生成每个 redis-server 服务实例自己独有的配置文件：redis-node?-$PORT.conf。

    **每次执行 config （$ redis_cluster_install.sh redis-cluster.settings config）都会重新自动生成配置目录 conf.$redis_cluster_id （从目录 conf.default 复制得到）。因此建议更改 conf.default 的内容而不是手动修改 conf.$redis_cluster_id。**

### TODO

- 服务器针对 redis 性能优化配置脚本

- 集群启用 ssl 证书

- hiredis 和 hiredis ssl 开发示例

2024-09-19, maparare.top