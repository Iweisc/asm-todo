; Linux x86-64 syscall numbers and the handful of kernel constants we use.

%define SYS_read            0
%define SYS_write           1
%define SYS_open            2
%define SYS_close           3
%define SYS_fstat           5
%define SYS_poll            7
%define SYS_lseek           8
%define SYS_getsockopt      55
%define SYS_epoll_wait      232
%define SYS_epoll_ctl       233
%define SYS_epoll_create1   291
%define SYS_mmap            9
%define SYS_munmap          11
%define SYS_rt_sigaction    13
%define SYS_socket          41
%define SYS_connect         42
%define SYS_sendmsg         46
%define SYS_recvmsg         47
%define SYS_bind            49
%define SYS_listen          50
%define SYS_setsockopt      54
%define SYS_exit            60
%define SYS_fsync           74
%define SYS_fdatasync       75
%define SYS_ftruncate       77
%define SYS_rename          82
%define SYS_mkdir           83
%define SYS_clock_gettime   228
%define SYS_accept4         288
%define SYS_memfd_create    319
%define SYS_getrandom       318
%define SYS_pipe2           293
%define SYS_pread64         17
%define SYS_unlink          87

%define EINTR               4
%define ENOENT              2
%define EAGAIN              11
%define EINPROGRESS         115

%define O_RDONLY            0
%define O_WRONLY            1
%define O_RDWR              2
%define O_CREAT             0x40
%define O_TRUNC             0x200
%define O_APPEND            0x400
%define O_NONBLOCK          0x800
%define O_DIRECTORY         0x10000
%define O_CLOEXEC           0x80000

%define STAT_SIZE           144
%define STAT_MODE           24          ; u32 in struct stat
%define S_IFMT              0o170000
%define S_IFREG             0o100000

%define AF_UNIX             1
%define AF_INET             2
%define SOCK_STREAM         1
%define SOCK_CLOEXEC        0x80000
%define SOCK_NONBLOCK       0x800
%define SO_ERROR            4
%define IPPROTO_TCP         6
%define TCP_NODELAY         1
%define SOL_SOCKET          1
%define SO_REUSEADDR        2
%define SO_RCVTIMEO         20
%define SO_SNDTIMEO         21
%define SCM_RIGHTS          1
%define MSG_CMSG_CLOEXEC    0x40000000

%define PROT_READ           1
%define PROT_RW             3
%define MAP_SHARED          1
%define MAP_PRIVATE         2
%define MAP_ANONYMOUS       0x20
%define MFD_CLOEXEC         1

%define POLLIN              1
%define POLLOUT             4
%define POLLERR             8
%define POLLHUP             16
%define EPOLLIN             1
%define EPOLLOUT            4
%define EPOLLERR            8
%define EPOLLHUP            16
%define EPOLL_CTL_ADD       1
%define EPOLL_CTL_MOD       3
%define CLOCK_REALTIME      0
%define CLOCK_MONOTONIC     1
%define SIGPIPE             13
%define SIG_IGN             1
