Pod::Spec.new do |s|
  s.name             = 'flutter_tor'
  s.version          = '0.1.0'
  s.summary          = 'Native Flutter plugin for Tor with obfs4/snowflake bridge support'
  s.homepage         = 'https://github.com/dmitry4567/flutter_tor'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'dmitry4567' => 'dmitry4567@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{swift,h,m}'
  s.swift_version    = '5.9'
  s.platform         = :ios, '15.0'

  s.dependency 'Flutter'
  s.dependency 'IPtProxy', '~> 5.3'

  # Автоматическая загрузка tor.xcframework при установке
  s.prepare_command = <<-CMD
    if [ ! -d "tor.xcframework" ]; then
      curl -L https://github.com/iCepa/Tor.framework/releases/download/v409.6.1/tor.xcframework.zip -o tor.xcframework.zip
      unzip -q tor.xcframework.zip
      rm tor.xcframework.zip
    fi
  CMD

  s.vendored_frameworks = 'tor.xcframework'
  s.libraries = 'z'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS'  => '-ObjC',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/tor.xcframework/ios-arm64/tor.framework/Headers" "${PODS_TARGET_SRCROOT}/tor.xcframework/ios-arm64_x86_64-simulator/tor.framework/Headers"'
  }
end
