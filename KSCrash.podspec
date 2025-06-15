Pod::Spec.new do |s|
  IOS_DEPLOYMENT_TARGET = '12.0' unless defined? IOS_DEPLOYMENT_TARGET
  s.name         = "KSCrash"
  s.version      = "2.2.0"
  s.summary      = "The Ultimate iOS Crash Reporter"
  s.homepage     = "https://github.com/kstenerud/KSCrash"
  s.license      = { :type => 'KSCrash license agreement', :file => 'LICENSE' }
  s.author       = { "Karl Stenerud" => "kstenerud@gmail.com" }
  s.ios.deployment_target = IOS_DEPLOYMENT_TARGET
  s.osx.deployment_target = '10.14'
  s.tvos.deployment_target = '12.0'
  s.watchos.deployment_target = '5.0'
  s.visionos.deployment_target =  '1.0'
  s.source       = { :git => "https://github.com/kstenerud/KSCrash.git", :tag=>s.version.to_s }
  s.frameworks   = 'Foundation'
  s.libraries    = 'c++', 'z'
  s.xcconfig     = { 'GCC_ENABLE_CPP_EXCEPTIONS' => 'YES' }
  s.default_subspecs = 'Installations'

  configure_subspec = lambda do |subs|
    module_name = subs.name.gsub('/', '')
    subs.source_files = "Sources/#{module_name}/**/*.{h,m,mm,c,cpp,def}"
    subs.public_header_files = "Sources/#{module_name}/include/*.h"
    subs.resource_bundles = { module_name => "Sources/#{module_name}/Resources/PrivacyInfo.xcprivacy" }
  end

  s.subspec 'Recording' do |recording|
    recording.dependency 'KSCrash/RecordingCore'

    configure_subspec.call(recording)
  end

  s.subspec 'Filters' do |filters|
    filters.dependency 'KSCrash/Recording'
    filters.dependency 'KSCrash/RecordingCore'
    filters.dependency 'KSCrash/ReportingCore'

    configure_subspec.call(filters)
  end

  s.subspec 'Sinks' do |sinks|
    sinks.dependency 'KSCrash/Recording'
    sinks.dependency 'KSCrash/Filters'
    sinks.ios.frameworks = 'MessageUI'

    configure_subspec.call(sinks)
  end

  s.subspec 'Installations' do |installations|
    installations.dependency 'KSCrash/Filters'
    installations.dependency 'KSCrash/Sinks'
    installations.dependency 'KSCrash/Recording'
    installations.dependency 'KSCrash/DemangleFilter'

    configure_subspec.call(installations)
  end

  s.subspec 'RecordingCore' do |recording_core|
    recording_core.dependency 'KSCrash/Core'

    configure_subspec.call(recording_core)
  end

  s.subspec 'BootTimeMonitor' do |boot_time_monitor|
    boot_time_monitor.dependency 'KSCrash/RecordingCore'

    configure_subspec.call(boot_time_monitor)
  end

  s.subspec 'DiscSpaceMonitor' do |disc_space_monitor|
    disc_space_monitor.dependency 'KSCrash/RecordingCore'

    configure_subspec.call(disc_space_monitor)
  end

  s.subspec 'DemangleFilter' do |demangle_filter|
    demangle_filter.dependency 'KSCrash/Recording'

    configure_subspec.call(demangle_filter)
  end

  s.subspec 'ReportingCore' do |reporting_core|
    reporting_core.dependency 'KSCrash/Core'
    reporting_core.ios.frameworks = 'SystemConfiguration'
    reporting_core.tvos.frameworks = 'SystemConfiguration'
    reporting_core.osx.frameworks = 'SystemConfiguration'

    configure_subspec.call(reporting_core)
  end

  s.subspec 'Core' do |core|
    configure_subspec.call(core)
  end
end
