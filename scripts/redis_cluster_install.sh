#!/bin/bash
#
# @file: redis_cluster_install.sh
#   redis 集群部署工具
#
# Usage:
#  redis_cluster_tool.sh /path/to/redis-cluster.settings ACTION
#  ACTION:
#     config     生成全部节点配置文件
#     build      编译 redis 源码
#     deploy     在当前节点上部署 redis 集群
#     clean      清理所有中间文件
#
# @author: 350137278@qq.com
#
# @create: 2024-09-14
#
# @update: 2024-09-18
#
########################################################################

########################################
# CentOS 7 使用 aliyum repo:
#   cd /etc/yum.repos.d/ && mkdir old_repos && mv ./*.repo old_repos
#   wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
#   yum clean all && yum makecache
#   yum list && update
# OpenSSL-devel: 
#   yum install openssl-devel zip unzip
# jemalloc:
#   cd jemalloc-5.2.1
#   ./autogen.sh --with-jemalloc-prefix=je_ --prefix=/usr/local
#   make -j 8
#   make install
########################################
_name_=$(basename "$0")
_cdir_=$(cd "$(dirname "$0")" && pwd)
_file_=""${_cdir}"/"${_name}""
_ver_="0.1.0"

. $_cdir_/common.sh

# Treat unset variables as an error
set -o nounset

# Treat any error as exit
set -o errexit

# 动作命令
has_config=""
has_build=""
has_deploy=""
has_clean=""

actions=($(echo "$*" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))

if [[ $(array_find actions "ALL") != -1 ]]; then
    has_config="y";
    has_build="y";
    has_deploy="y";
else
    if [[ $(array_find actions "config") != -1 ]]; then has_config="y"; fi
    if [[ $(array_find actions "build") != -1 ]]; then has_build="y"; fi
    if [[ $(array_find actions "deploy") != -1 ]]; then has_deploy="y"; fi
    if [[ $(array_find actions "clean") != -1 ]]; then has_clean="y"; fi
fi

# 测试是否是 root 用户
loguser=`id -un`
echoinfo "当前登录为：$loguser"
chk_root

# 配置文件
redis_config_file="$1"
config_path=$(cd "$(dirname "$1")" && pwd)
config_file=$(basename "$1")

config_path_file="$config_path/$config_file"
echoinfo "cluster config: $config_path_file"

# 应入配置环境变量
. "$config_path_file"

# redis cluster id 必须是小写字母单词, 不可以是系统路径名称!
# TODO: 加入其他校验...
echoinfo "redis cluster id: $redis_cluster_id"
if [ "$redis_cluster_id" = "default" ]; then
    echoerror "illegal redis cluster id: $redis_cluster_id"
    exit -1
fi

# 集群安装目录
redis_install_prefix="$redis_cluster_dir/$redis_cluster_id"
cluster_home_dir=$(echo "$redis_install_prefix" | sed 's/\//\\\//g')

# redis-7.4.0.tar.gz
redis_tarball_name=$(basename $redis_wget_url)

# 包下载目录
redis_downloads_dir="$_cdir_/downloads"

build_success_dir="$_cdir_/BUILD.SUCCESS"
config_success_dir="$config_path/conf.$redis_cluster_id"

# https://www.cnblogs.com/chien/p/17328546.html
# redis
redis_name=$(echo "${redis_tarball_name%.tar.gz*}" | awk -F '[-]' '{print $1}')

# 7.4.0
redis_verno=$(echo "${redis_tarball_name%.tar.gz*}" | awk -F '[-]' '{print $2}')

if [ "$redis_tarball_name" != "$redis_name""-""$redis_verno"".tar.gz" ]; then
    echoerror "not a redis tarball: $redis_tarball_name"
    exit -1
fi

# 源码路径
redis_srcdir="$redis_downloads_dir/$redis_name""-""$redis_verno/src"


################################################################
function download_redis() {
    # 检查文件是否正确并自动下载# 包文件路径名
    # /opt/redis/downloads/redis-7.4.0.tar.gz
    redis_pkg_file="$redis_downloads_dir/$redis_tarball_name"

    ret=$(file_cksum "$redis_pkg_file" "$redis_tarball_md5sum")
    if [ "$ret" = "0" ]; then
        echoinfo "tarball file exists: $redis_pkg_file"
    elif [ "$ret" = "1" ]; then
        echoerror "file md5sum ($redis_tarball_md5sum) failed: $redis_pkg_file"
        exit -1
    else
        # 检查文件是否正确
        echowarn "tarball file not exist: $redis_pkg_file"
        echoinfo "  download: $redis_wget_url => $redis_pkg_file"
        wget -T "$redis_wget_timeout" -P "$redis_downloads_dir" "$redis_wget_url"
    fi

    # 再次检查文件是否正确
    ret=$(file_cksum "$redis_pkg_file" "$redis_tarball_md5sum")
    if [ "$ret" != "0" ]; then
        echoerror "file md5sum ($redis_tarball_md5sum) failed: $redis_pkg_file"
        exit -1
    fi
}


function download_hiredis() {
    # /opt/redis/downloads/hiredis-master.zip
    hiredis_zip_file="$redis_downloads_dir/hiredis-master.zip"

    ret=$(file_cksum "$hiredis_zip_file" "$hiredis_zip_md5sum")
    if [ "$ret" = "0" ]; then
        echoinfo "zip file exists: $hiredis_zip_file"
    elif [ "$ret" = "1" ]; then
        echoerror "file md5sum (hiredis-master.zip) failed: $hiredis_zip_file"
        exit -1
    else
        # 检查文件是否正确
        echowarn "zip file not exist: $hiredis_zip_file"
        echoinfo "  download: $hiredis_wget_url => $hiredis_zip_file"
        wget -T "$redis_wget_timeout" -P "$redis_downloads_dir" -O "$redis_downloads_dir/hiredis-master.zip" "$hiredis_wget_url"
    fi

    # 再次检查文件是否正确
    ret=$(file_cksum "$hiredis_zip_file" "$hiredis_zip_md5sum")
    if [ "$ret" != "0" ]; then
        echoerror "file md5sum (hiredis-master.zip) failed: $hiredis_zip_file"
        exit -1
    fi
}


function build() {
    if [ -L "$build_success_dir" ] && [ -e "$build_success_dir" ]; then
        # 是软链接, 并且存在
        if [ ! -d "$redis_srcdir" ]; then
            unlink "$build_success_dir"
        fi
    fi

    if [ ! $has_build ]; then
        return
    fi

    # 编译源码
    echoinfo "build redis (BUILD_TLS=$build_tls_mode): $redis_srcdir"

    if [ ! -L "$build_success_dir" ] || [ ! -e "$build_success_dir" ]; then
        # 软链接无效
        rm -rf "$build_success_dir"

        # 解压并编译 redis
        cd "$redis_downloads_dir" && rm -rf "$redis_srcdir" && tar xvf "$redis_tarball_name"
        cd "$redis_srcdir" && make BUILD_TLS="$build_tls_mode" -j 4

        # 解压并编译 hiredis
        cd "$redis_downloads_dir" && rm -rf "hiredis-master" && unzip hiredis-master.zip
        cd "hiredis-master" && make USE_SSL=1

        # 全部成功创建连接 BUILD_SUCCESS
        ln -s $(dirname "$redis_srcdir") "$build_success_dir"
    fi
}


function config() {
    # 创建集群配置目录(每天新建)
    daydir=$(date +"%Y%m%d_%H%M")

    # 节点配置文件路径
    nodes_conf_dir="$config_success_dir.$daydir"

    # 节点配置 ini 文件
    nodes_ini_file="$nodes_conf_dir/cluster_nodes.ini"

     # 创建集群配置目录
    echoinfo "create cluster config: $nodes_conf_dir"
    echoinfo "cluster nodes ini: $nodes_ini_file"

    rm -rf "$config_success_dir"
    rm -rf "$nodes_conf_dir"

    cp -r "$_cdir_/conf.default" "$nodes_conf_dir"

    # 生成 redis 集群初始创建脚本: 包含集群全部节点, 在任意节点执行一次即可!
    > "$nodes_conf_dir/CLUSTER_NODES.LIST"

    ################ 为每个节点的每个实例生成配置文件 ################
    # 根据节点配置文件模板动态对每个服务器生成实例的配置文件:
    #  每个服务器节点运行多个 redis-server 实例;
    #  每个 redis-server 实例使用专有的配置文件 redis-NODEID-PORT.conf 启动
    nodes=$(read_cfg "$nodes_ini_file" "redis_cluster" "nodes")
    nodeslist=($(echo "$nodes" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))

    numnodes=${#nodeslist[@]}
    for (( n=0; n<${numnodes}; n++ ));
    do
        nodeid="${nodeslist[n]}"

        # 节点配置文件存放目录
        node_conf_dir="$nodes_conf_dir/$nodeid"
        mkdir -p "$node_conf_dir"

        # 实例配置文件: node1-6377.conf node1-6378.conf node1-6379.conf
        host=$(read_cfg "$nodes_ini_file" "$nodeid" "host")
        echoinfo "[$nodeid] create conf files for host: $host"

        # 节点配置文件模板: 用于生成实际的实例配置文件
        node_conf0_file="$nodes_conf_dir""/"$(read_cfg "$nodes_ini_file" "$nodeid" "conf")

        addrs=$(read_cfg "$nodes_ini_file" "$nodeid" "addrs")
        addrslist=($(echo "$addrs" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))
        addrstr="${addrslist[@]}"

        ports=$(read_cfg "$nodes_ini_file" "$nodeid" "ports")
        portslist=($(echo "$ports" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))

        # 节点启动脚本: 启动节点全并服务实例
        echo "#!/bin/bash" > "$node_conf_dir/start_redis.sh"
        echo "cd $redis_install_prefix" >> "$node_conf_dir/start_redis.sh"

        # 节点关闭脚本: 保存并关闭节点全部服务实例
        echo "#!/bin/bash" > "$node_conf_dir/shutdown_redis.sh"
        echo "cd $redis_install_prefix" >> "$node_conf_dir/shutdown_redis.sh"

        numports=${#portslist[@]}
        for (( p=0; p<${numports}; p++ ));
        do
            port="${portslist[p]}"
            node_conf_file="$node_conf_dir/redis-$nodeid-$port.conf"

            echo "$host:$port" >> "$nodes_conf_dir/CLUSTER_NODES.LIST"

            echoinfo "create node conf: $node_conf_file"

            cat "$node_conf0_file" | \
                sed 's/'"{"CLUSTER_HOME_DIR"}"'/'"$cluster_home_dir"'/g' | \
                sed 's/'"{"CLUSTERID"}"'/'"$redis_cluster_id"'/g' | \
                sed 's/'"{"NODEID"}"'/'"$nodeid"'/g' | \
                sed 's/'"{"RDB_DIR"}"'/'"$rdb_dir_name"'/g' | \
                sed 's/'"{"HOST"}"'/'"$host"'/g' | \
                sed 's/'"{"PORT"}"'/'"$port"'/g' | \
                sed 's/'"{"ADDRS"}"'/'"$addrstr"'/g' | \
                sed 's/'"{"PASSWORD"}"'/'"$redis_cluster_pass"'/g' \
            > "$node_conf_file"

            echo "./bin/redis-server ./conf/$(basename $node_conf_file)" >> "$node_conf_dir/start_redis.sh"
            echo "./bin/redis-cli -a "'"'"$redis_cluster_pass"'"'" -h $host -p $port SHUTDOWN" >> "$node_conf_dir/shutdown_redis.sh"
        done
    done

    # 生成 redis 集群初始创建脚本
    echo "#!/bin/bash" > "$nodes_conf_dir/create_cluster.sh"
    echo "" >> "$nodes_conf_dir/create_cluster.sh"
    echo "$redis_install_prefix/bin/redis-cli -a "'"'"$redis_cluster_pass"'"'" \\" >> "$nodes_conf_dir/create_cluster.sh"
    echo "    --cluster-replicas $redis_cluster_replicas \\" >> "$nodes_conf_dir/create_cluster.sh"
    echo "    --cluster create \\" >> "$nodes_conf_dir/create_cluster.sh"
    cat "$nodes_conf_dir/CLUSTER_NODES.LIST" | awk '{ print "      "$0" \\" }' >> "$nodes_conf_dir/create_cluster.sh"
    echo ";" >> "$nodes_conf_dir/create_cluster.sh"

    # 创建成功连接
    ln -s "$nodes_conf_dir" "$config_success_dir"
}


function deploy() {
    if [ ! -e "$build_success_dir" ]; then
        echoerror "deploy depends on a success build: $build_success_dir"
        echo " you might try the below command:"
        echo "    $ sudo $_cdir/$_file_ ${actions[0]} build deploy"
        exit -1
    fi

    # 部署 redis 集群软件
    echoinfo "deploy redis cluster at: $redis_install_prefix"

    sleep 3

    cd "$build_success_dir/src" && make install PREFIX="$redis_install_prefix"

    mkdir -p "$redis_install_prefix/$rdb_dir_name"
    mkdir -p "$redis_install_prefix/conf"
    mkdir -p "$redis_install_prefix/log"
    mkdir -p "$redis_install_prefix/run"
    mkdir -p "$redis_install_prefix/module"

    # 节点配置 ini 文件
    nodes_ini_file="$config_success_dir/cluster_nodes.ini"

    ################ 为每个节点的每个实例生成配置文件 ################
    # 根据节点配置文件模板动态对每个服务器生成实例的配置文件:
    #  每个服务器节点运行多个 redis-server 实例;
    #  每个 redis-server 实例使用专有的配置文件 redis-NODEID-PORT.conf 启动
    nodes=$(read_cfg "$nodes_ini_file" "redis_cluster" "nodes")
    nodeslist=($(echo "$nodes" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))

    numnodes=${#nodeslist[@]}
    for (( n=0; n<${numnodes}; n++ ));
    do
        nodeid="${nodeslist[n]}"

        # 节点配置文件存放目录
        node_conf_dir="$config_success_dir/$nodeid"

        # 实例配置文件: node1-6377.conf node1-6378.conf node1-6379.conf
        host=$(read_cfg "$nodes_ini_file" "$nodeid" "host")

        addrs=$(read_cfg "$nodes_ini_file" "$nodeid" "addrs")
        addrslist=($(echo "$addrs" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))
        addrstr="${addrslist[@]}"

        ports=$(read_cfg "$nodes_ini_file" "$nodeid" "ports")
        portslist=($(echo "$ports" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))

        numports=${#portslist[@]}
        for (( p=0; p<${numports}; p++ ));
        do
            port="${portslist[p]}"
            node_conf_file="$node_conf_dir/redis-$nodeid-$port.conf"

            # 部署实例配置文件
            if [ "$(hostname)" = "$host" ]; then
                # 仅在本机节点部署
                cp "$node_conf_file" "$redis_install_prefix/conf/"
                echoinfo "deploy node conf: $redis_install_prefix/conf/$(basename $node_conf_file)"
            fi
        done

        # 部署集群初始创建脚本
        if [ "$(hostname)" = "$host" ]; then
            # 仅在本机节点部署
            cp "$node_conf_dir/start_redis.sh" "$redis_install_prefix/"
            cp "$node_conf_dir/shutdown_redis.sh" "$redis_install_prefix/"
            cp "$config_success_dir/create_cluster.sh" "$redis_install_prefix/"

            chmod +x "$redis_install_prefix/start_redis.sh"
            chmod +x "$redis_install_prefix/shutdown_redis.sh"
            chmod +x "$redis_install_prefix/create_cluster.sh"

            echo "#!/bin/bash" > "$redis_install_prefix/connect_redis.sh"
            echo "$redis_install_prefix/bin/redis-cli -c -a "'"'"$redis_cluster_pass"'"'" -h $host -p ${portslist[0]}" >> "$redis_install_prefix/connect_redis.sh"
            chmod +x "$redis_install_prefix/connect_redis.sh"
        fi
    done

    cd "$redis_downloads_dir/hiredis-master" && make USE_SSL=1 PREFIX="$redis_install_prefix" install
    cp "$build_success_dir/redis.conf" "$redis_install_prefix/redis.conf.default"

    echoinfo "hiredis install at: $redis_install_prefix"
    echoinfo "redis cluster deploy success: $redis_install_prefix"
}


function clean() {
    echowarn "remove redis at: $(dirname $redis_srcdir)"
    rm -rf "$build_success_dir"
    rm -rf "$redis_downloads_dir/$(dirname $redis_srcdir)"

    echowarn "remove hiredis at: $redis_downloads_dir/hiredis-master"
    rm -rf "$redis_downloads_dir/hiredis-master"

    echowarn "remove redis conf at: $(dirname $redis_srcdir)"
    rm -rf "$config_success_dir"

    echoinfo "redis clean all success"
}

################################################################
download_redis && download_hiredis;

if [ $has_clean ]; then clean; fi;

if [ $has_build ]; then build; fi;

if [ $has_config ]; then config; fi;

if [ $has_deploy ]; then deploy; fi;

exit 0;