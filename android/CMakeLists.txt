cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "libsmb2_flutter")
project(${PROJECT_NAME} LANGUAGES C)

set(LIBSMB2_SOURCES
    "../libsmb2/lib/libsmb2.c"
    "../libsmb2/lib/smb2-cmd-close.c"
    "../libsmb2/lib/smb2-cmd-create.c"
    "../libsmb2/lib/smb2-cmd-echo.c"
    "../libsmb2/lib/smb2-cmd-error.c"
    "../libsmb2/lib/smb2-cmd-flush.c"
    "../libsmb2/lib/smb2-cmd-ioctl.c"
    "../libsmb2/lib/smb2-cmd-lock.c"
    "../libsmb2/lib/smb2-cmd-logoff.c"
    "../libsmb2/lib/smb2-cmd-negotiate.c"
    "../libsmb2/lib/smb2-cmd-notify-change.c"
    "../libsmb2/lib/smb2-cmd-oplock-break.c"
    "../libsmb2/lib/smb2-cmd-query-directory.c"
    "../libsmb2/lib/smb2-cmd-query-info.c"
    "../libsmb2/lib/smb2-cmd-read.c"
    "../libsmb2/lib/smb2-cmd-session-setup.c"
    "../libsmb2/lib/smb2-cmd-set-info.c"
    "../libsmb2/lib/smb2-cmd-tree-connect.c"
    "../libsmb2/lib/smb2-cmd-tree-disconnect.c"
    "../libsmb2/lib/smb2-cmd-write.c"
    "../libsmb2/lib/smb2-data-file-info.c"
    "../libsmb2/lib/smb2-data-filesystem-info.c"
    "../libsmb2/lib/smb2-data-security-descriptor.c"
    "../libsmb2/lib/smb2-data-reparse-point.c"
    "../libsmb2/lib/smb2-share-enum.c"
    "../libsmb2/lib/smb2-signing.c"
    "../libsmb2/lib/smb3-seal.c"
    "../libsmb2/lib/krb5-wrapper.c"
    "../libsmb2/lib/init.c"
    "../libsmb2/lib/pdu.c"
    "../libsmb2/lib/socket.c"
    "../libsmb2/lib/sync.c"
    "../libsmb2/lib/timestamps.c"
    "../libsmb2/lib/ntlmssp.c"
    "../libsmb2/lib/hmac-md5.c"
    "../libsmb2/lib/hmac.c"
    "../libsmb2/lib/md4c.c"
    "../libsmb2/lib/md5.c"
    "../libsmb2/lib/sha1.c"
    "../libsmb2/lib/sha224-256.c"
    "../libsmb2/lib/sha384-512.c"
    "../libsmb2/lib/aes.c"
    "../libsmb2/lib/aes_reference.c"
    "../libsmb2/lib/aes128ccm.c"
    "../libsmb2/lib/alloc.c"
    "../libsmb2/lib/errors.c"
    "../libsmb2/lib/unicode.c"
    "../libsmb2/lib/compat.c"
    "../libsmb2/lib/asn1-ber.c"
    "../libsmb2/lib/spnego-wrapper.c"
    "../libsmb2/lib/usha.c"
    "../libsmb2/lib/dcerpc.c"
    "../libsmb2/lib/dcerpc-lsa.c"
    "../libsmb2/lib/dcerpc-srvsvc.c"
)

add_library(${PROJECT_NAME} SHARED
    ${LIBSMB2_SOURCES}
    "src/libsmb2_flutter_plugin.c"
)

target_compile_definitions(${PROJECT_NAME} PRIVATE
    HAVE_CONFIG_H
    ANDROID
)

target_compile_options(${PROJECT_NAME} PRIVATE
    -include
    "${CMAKE_CURRENT_SOURCE_DIR}/src/android_config.h"
)

target_include_directories(${PROJECT_NAME} PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/../libsmb2/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/../libsmb2/include/smb2"
    "${CMAKE_CURRENT_SOURCE_DIR}/../libsmb2/lib"
)

target_link_libraries(${PROJECT_NAME} PRIVATE
    log
)

set_target_properties(${PROJECT_NAME} PROPERTIES
    PUBLIC_HEADER "include/libsmb2_wrapper.h"
    OUTPUT_NAME "libsmb2_flutter"
)
