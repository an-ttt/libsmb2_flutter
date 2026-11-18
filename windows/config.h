#ifndef CONFIG_H
#define CONFIG_H
#define HAVE_CONFIG_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_TIME_H 1

#define PACKAGE_VERSION "4.0.0"

#ifdef _MSC_VER
  #define inline __inline
  #define __attribute__(x)
  #define strcasecmp _stricmp
  #define strncasecmp _strnicmp
  #define _U_ __pragma(warning(suppress:4100))

  #ifndef O_RDONLY
  #define O_RDONLY 0x0000
  #endif
  #ifndef O_WRONLY
  #define O_WRONLY 0x0001
  #endif
  #ifndef O_RDWR
  #define O_RDWR   0x0002
  #endif
  #ifndef O_CREAT
  #define O_CREAT  0x0100
  #endif
  #ifndef O_TRUNC
  #define O_TRUNC  0x0200
  #endif
  #ifndef O_EXCL
  #define O_EXCL   0x0400
  #endif
  #ifndef O_APPEND
  #define O_APPEND 0x0008
  #endif

  #define HAVE_LINGER 1
#else
  #define snprintf _snprintf
  #define inline __inline
  #define __attribute__(x)
  #define strcasecmp _stricmp
  #define strncasecmp _strnicmp
  #define _U_
#endif

#endif
