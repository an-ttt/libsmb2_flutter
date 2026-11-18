cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "libsmb2_flutter")
project(${PROJECT_NAME} LANGUAGES C)

set(LIBSMB2_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../libsmb2")

set(LIBSMB2_SOURCES
    "${LIBSMB2_DIR}/lib/libsmb2.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-close.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-create.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-echo.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-error.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-flush.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-ioctl.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-lock.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-logoff.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-negotiate.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-notify-change.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-oplock-break.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-query-directory.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-query-info.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-read.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-session-setup.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-set-info.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-tree-connect.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-tree-disconnect.c"
    "${LIBSMB2_DIR}/lib/smb2-cmd-write.c"
    "${LIBSMB2_DIR}/lib/smb2-data-file-info.c"
    "${LIBSMB2_DIR}/lib/smb2-data-filesystem-info.c"
    "${LIBSMB2_DIR}/lib/smb2-data-security-descriptor.c"
    "${LIBSMB2_DIR}/lib/smb2-data-reparse-point.c"
    "${LIBSMB2_DIR}/lib/smb2-share-enum.c"
    "${LIBSMB2_DIR}/lib/smb2-signing.c"
    "${LIBSMB2_DIR}/lib/smb3-seal.c"
    "${LIBSMB2_DIR}/lib/init.c"
    "${LIBSMB2_DIR}/lib/pdu.c"
    "${LIBSMB2_DIR}/lib/socket.c"
    "${LIBSMB2_DIR}/lib/sync.c"
    "${LIBSMB2_DIR}/lib/timestamps.c"
    "${LIBSMB2_DIR}/lib/ntlmssp.c"
    "${LIBSMB2_DIR}/lib/hmac-md5.c"
    "${LIBSMB2_DIR}/lib/hmac.c"
    "${LIBSMB2_DIR}/lib/md4c.c"
    "${LIBSMB2_DIR}/lib/md5.c"
    "${LIBSMB2_DIR}/lib/sha1.c"
    "${LIBSMB2_DIR}/lib/sha224-256.c"
    "${LIBSMB2_DIR}/lib/sha384-512.c"
    "${LIBSMB2_DIR}/lib/aes.c"
    "${LIBSMB2_DIR}/lib/aes_reference.c"
    "${LIBSMB2_DIR}/lib/aes128ccm.c"
    "${LIBSMB2_DIR}/lib/alloc.c"
    "${LIBSMB2_DIR}/lib/errors.c"
    "${LIBSMB2_DIR}/lib/unicode.c"
    "${LIBSMB2_DIR}/lib/compat.c"
    "${LIBSMB2_DIR}/lib/asn1-ber.c"
    "${LIBSMB2_DIR}/lib/spnego-wrapper.c"
    "${LIBSMB2_DIR}/lib/usha.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/win_compat.c"
    "${LIBSMB2_DIR}/lib/dcerpc.c"
    "${LIBSMB2_DIR}/lib/dcerpc-lsa.c"
    "${LIBSMB2_DIR}/lib/dcerpc-srvsvc.c"
)

set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS TRUE)

add_library(${PROJECT_NAME} SHARED
    ${LIBSMB2_SOURCES}
    "src/libsmb2_flutter_plugin.c"
)

target_compile_definitions(${PROJECT_NAME} PRIVATE
    HAVE_CONFIG_H
    _CRT_SECURE_NO_WARNINGS
    _WINSOCK_DEPRECATED_NO_WARNINGS
    WIN32_LEAN_AND_MEAN
)

if(MSVC)
    target_compile_options(${PROJECT_NAME} PRIVATE
        /wd4005
        /wd4244
        /wd4267
        /wd4018
        /wd4101
    )
endif()

target_include_directories(${PROJECT_NAME} PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${LIBSMB2_DIR}/include"
    "${LIBSMB2_DIR}/include/smb2"
    "${LIBSMB2_DIR}/lib"
)

target_link_libraries(${PROJECT_NAME} PRIVATE
    ws2_32
    secur32
    bcrypt
)

set_target_properties(${PROJECT_NAME} PROPERTIES
    OUTPUT_NAME "libsmb2_flutter"
)

set(libsmb2_flutter_bundled_libraries
    "$<TARGET_FILE:${PROJECT_NAME}>"
    PARENT_SCOPE
)
