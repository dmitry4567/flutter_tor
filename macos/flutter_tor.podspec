Pod::Spec.new do |s|
  s.name             = 'flutter_tor'
  s.version          = '0.2.0'
  s.summary          = 'Native Flutter plugin for Tor with obfs4/snowflake bridge support'
  s.homepage         = 'https://github.com/dmitry4567/flutter_tor'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'dmitry4567' => 'dmitry4567@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{swift,h,m}'
  s.swift_version    = '5.9'
  s.platform         = :osx, '12.0'

  s.dependency 'FlutterMacOS'
  s.dependency 'IPtProxy', '~> 5.3'

  s.prepare_command = <<-CMD
    if [ ! -d "tor.xcframework" ]; then
      curl -L https://github.com/iCepa/Tor.framework/releases/download/v409.6.1/tor.xcframework.zip -o tor.xcframework.zip
      unzip -q tor.xcframework.zip
      rm tor.xcframework.zip
    fi
  CMD

  s.vendored_frameworks = 'tor.xcframework'
  s.libraries = 'z', 'resolv'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS'  => '-ObjC',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/tor.xcframework/macos-arm64_x86_64/tor.framework/Headers"'
  }
end
