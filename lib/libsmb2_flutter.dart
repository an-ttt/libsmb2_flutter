library;

export 'src/smb_isolate.dart';
// 暴露 O_* / 写入标志，便于单测与真机测试断言「flag → CreateDisposition」
// 的平台常量没有再次错位（D-1 根因）。
export 'src/smb_platform.dart';
