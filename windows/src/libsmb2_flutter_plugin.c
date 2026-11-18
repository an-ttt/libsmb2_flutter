#ifdef _WIN32
#define LIBSMB2_FLUTTER_EXPORT __declspec(dllexport)
#include <winsock2.h>
#include <windows.h>
#else
#define LIBSMB2_FLUTTER_EXPORT
#endif

LIBSMB2_FLUTTER_EXPORT void libsmb2_flutter_plugin_register(void* registrar) {
}
