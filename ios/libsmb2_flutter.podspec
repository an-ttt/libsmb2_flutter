Pod::Spec.new do |s|
  s.name             = 'libsmb2_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Flutter FFI plugin for libsmb2'
  s.description      = <<-DESC
Flutter FFI plugin for libsmb2 - SMB/CIFS client library
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :type => 'LGPL-2.1' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*', 'libsmb2_lib/*.{c,h}'
  s.public_header_files = 'Classes/**/*.h'
  s.exclude_files    = [
    'libsmb2_lib/ps2/**/*',
    'libsmb2_lib/win_compat.c',
    'libsmb2_lib/krb5-wrapper.c',
    'libsmb2_lib/aes_reference.c'
  ]

  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'

  s.frameworks = 'CoreFoundation', 'Security'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/libsmb2/include/apple" "${PODS_TARGET_SRCROOT}/libsmb2/include" "${PODS_TARGET_SRCROOT}/libsmb2/include/smb2" "${PODS_TARGET_SRCROOT}/libsmb2_lib"',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'HAVE_CONFIG_H=1 _U_='
  }
  s.swift_version = '5.0'
end
