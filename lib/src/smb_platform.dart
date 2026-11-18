// ignore_for_file: constant_identifier_names
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'smb_bindings_generated.dart';

const int O_RDONLY = 0x0000;
const int O_WRONLY = 0x0001;
const int O_RDWR = 0x0002;
const int O_APPEND = 0x0008;

/// libsmb2 的 C 侧 `open_flags_to_create_request()`
/// （`libsmb2/lib/libsmb2.c` 的 create disposition 分支）用编译平台的
/// `O_CREAT / O_EXCL / O_TRUNC` 决定 SMB2 CREATE 的 CreateDisposition：
///   O_CREAT | O_TRUNC       -> FILE_OVERWRITE_IF（服务端截断到 0）
///   O_CREAT（无 O_TRUNC）   -> FILE_OPEN_IF（★不截断★）
///   O_CREAT | O_EXCL        -> FILE_CREATE（同名存在则打开失败）
///
/// 这里的位必须和 C 编译时使用的头文件完全一致，否则 FFI 传进去的位会落错。
/// 旧实现只区分 Windows，其它平台一律按 Linux/Bionic 的 0x40/0x80/0x200：
///   - Android/Linux (Bionic <fcntl.h>)：O_CREAT=0x0040 O_EXCL=0x0080 O_TRUNC=0x0200
///   - macOS/iOS     (Darwin <fcntl.h>)：O_CREAT=0x0200 O_EXCL=0x0800 O_TRUNC=0x0400
///     旧代码在 Darwin 传 0x0241，C 侧只看到 O_CREAT(0x0200)、O_TRUNC 丢失，
///     退化为 FILE_OPEN_IF：短清单覆盖长清单时旧内容的尾部原样残留。
///   - Windows (windows/config.h 的 _MSC_VER 分支)：
///     O_CREAT=0x0100 O_EXCL=0x0400 O_TRUNC=0x0200
///     旧代码传 0x0501 被解读成 O_CREAT|O_EXCL，退化为 FILE_CREATE。
///
/// 数值依据：Android NDK aarch64 <fcntl.h>、macOS SDK <fcntl.h>、
/// 本仓库 windows/config.h 的实际预处理结果；协议语义见 [MS-SMB2] 2.2.13。
int get oCreat {
  if (Platform.isWindows) return 0x0100;
  if (Platform.isAndroid || Platform.isLinux) return 0x0040;
  return 0x0200; // macOS / iOS
}

int get oExcl {
  if (Platform.isWindows) return 0x0400;
  if (Platform.isAndroid || Platform.isLinux) return 0x0080;
  return 0x0800; // macOS / iOS
}

int get oTrunc {
  if (Platform.isWindows) return 0x0200;
  if (Platform.isAndroid || Platform.isLinux) return 0x0200;
  return 0x0400; // macOS / iOS
}

/// 上传文件的完整打开标志（单一来源，便于日志与回归断言）。
int get smbWriteOpenFlags => O_WRONLY | oCreat | oTrunc;

final class WSADATA extends Struct {
  @Uint16()
  external int wVersion;
  @Uint16()
  external int wHighVersion;
  @Array(256)
  external Array<Uint8> szDescription;
  @Array(128)
  external Array<Uint8> szSystemStatus;
}

class LibSmb2 {
  static DynamicLibrary? _lib;
  static LibSmb2Bindings? _bindings;
  static bool _wsaInitialized = false;

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      debugPrint('Loading libsmb2 on Android');
      return DynamicLibrary.open('liblibsmb2_flutter.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('libsmb2_flutter.dll');
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libsmb2_flutter.so');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open(
          '@rpath/libsmb2_flutter.framework/Versions/A/libsmb2_flutter');
    }
    if (Platform.isIOS) {
      // iOS 上 podspec 以静态源码（source_files）方式将 libsmb2 编译进主可执行文件，
      // 不存在独立动态库，符号需从当前进程镜像中查找。
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Unsupported platform');
  }

  static LibSmb2Bindings get bindings {
    _lib ??= _openLibrary();
    _bindings ??= LibSmb2Bindings(_lib!);
    return _bindings!;
  }

  static bool initWinsock() {
    if (!Platform.isWindows) return true;
    if (_wsaInitialized) return true;

    final ws2Lib = DynamicLibrary.open('ws2_32.dll');
    final wsaStartup = ws2Lib.lookupFunction<
        Int32 Function(Uint16, Pointer<WSADATA>),
        int Function(int, Pointer<WSADATA>)>('WSAStartup');

    final wsaData = calloc<WSADATA>();
    final result = wsaStartup(0x0202, wsaData);
    calloc.free(wsaData);

    if (result != 0) {
      debugPrint('WSAStartup failed with error: $result');
      return false;
    }

    _wsaInitialized = true;
    debugPrint('Winsock initialized successfully');
    return true;
  }

  static void cleanupWinsock() {
    if (!Platform.isWindows || !_wsaInitialized) return;

    final ws2Lib = DynamicLibrary.open('ws2_32.dll');
    final wsaCleanup = ws2Lib.lookupFunction<
        Int32 Function(),
        int Function()>('WSACleanup');

    wsaCleanup();
    _wsaInitialized = false;
    debugPrint('Winsock cleaned up');
  }
}
