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

  s.source_files     = 'libsmb2/lib/*.{c,h}'
  s.exclude_files    = [
    'libsmb2/lib/ps2/**/*',
    'libsmb2/lib/win_compat.c',
    'libsmb2/lib/krb5-wrapper.c',
    'libsmb2/lib/aes_reference.c'
  ]

  s.ios.source_files = 'ios/Classes/**/*'
  s.osx.source_files = 'macos/Classes/**/*'
  s.ios.public_header_files = 'ios/Classes/**/*.h'
  s.osx.public_header_files = 'macos/Classes/**/*.h'

  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  s.frameworks = 'CoreFoundation', 'Security'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/libsmb2/include/apple" "${PODS_TARGET_SRCROOT}/libsmb2/include" "${PODS_TARGET_SRCROOT}/libsmb2/include/smb2" "${PODS_TARGET_SRCROOT}/libsmb2/lib"',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'HAVE_CONFIG_H=1 _U_='
  }
  s.swift_version = '5.0'
end
