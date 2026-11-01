Pod::Spec.new do |s|
  s.name             = 'sarcade_car'
  s.version          = '1.0.0'
  s.summary          = 'SARCADE in the car: CarPlay screen with tabs (lot 17, step 2b)'
  s.homepage         = 'https://github.com/sdubos-consulting/sarcade-app'
  s.license          = { :type => 'MPL-2.0' }
  s.author           = { 'SDUBOS Consulting' => 'github@sdubos.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.frameworks       = 'CarPlay', 'AVFoundation'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
end
