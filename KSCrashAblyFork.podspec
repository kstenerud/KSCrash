Pod::Spec.new do |s|
  IOS_DEPLOYMENT_TARGET = '6.0' unless defined? IOS_DEPLOYMENT_TARGET
  s.name         = "KSCrashAblyFork"
  s.version      = "1.15.8-ably-2"
  s.summary      = "The Ultimate iOS Crash Reporter"
  s.homepage     = "https://github.com/ably-forks/KSCrash"
  s.license     = { :type => 'KSCrash license agreement', :file => 'LICENSE' }
  s.author       = { "Karl Stenerud" => "kstenerud@gmail.com" }
  s.ios.deployment_target =  IOS_DEPLOYMENT_TARGET
  s.osx.deployment_target =  '10.8'
  s.tvos.deployment_target =  '9.0'
  s.watchos.deployment_target =  '2.0'
  s.source       = { :git => "https://github.com/ably-forks/KSCrash.git", :tag => s.version.to_s }
  s.frameworks = 'Foundation'
  s.libraries = 'c++', 'z'
  s.xcconfig = { 'GCC_ENABLE_CPP_EXCEPTIONS' => 'YES' }
  s.default_subspecs = 'Installations'

  s.subspec 'Recording' do |recording|
    recording.source_files   = 'Source/KSCrash/Recording/**/*.{h,m,mm,c,cpp}',
                               'Source/KSCrash/llvm/**/*.{h,m,mm,c,cpp}',
                               'Source/KSCrash/swift/**/*.{h,m,mm,c,cpp}',
                               'Source/KSCrash/Reporting/Filters/KSCrashReportFilter.h'
    recording.public_header_files = 'Source/KSCrash/Recording/KSCrash.h',
                                    'Source/KSCrash/Recording/KSCrashC.h',
                                    'Source/KSCrash/Recording/KSCrashReportWriter.h',
                                    'Source/KSCrash/Recording/Monitors/KSCrashMonitorType.h',
                                    'Source/KSCrash/Reporting/Filters/KSCrashReportFilter.h',
                                    'Source/KSCrash/Reporting/Filters/KSCrashReportFields.h'

    recording.subspec 'Tools' do |tools|
      tools.source_files = 'Source/KSCrash/Recording/Tools/*.h'
    end
  end

  s.subspec 'Reporting' do |reporting|
    reporting.dependency 'KSCrashAblyFork/Recording'

    reporting.subspec 'Filters' do |filters|
      filters.subspec 'Base' do |base|
        base.source_files = 'Source/KSCrash/Reporting/Filters/Tools/**/*.{h,m,mm,c,cpp}',
                            'Source/KSCrash/Reporting/Filters/KSCrashReportFilter.h'
        base.public_header_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilter.h'
      end

      filters.subspec 'Alert' do |alert|
        alert.dependency 'KSCrashAblyFork/Reporting/Filters/Base'
        alert.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterAlert.h',
                             'Source/KSCrash/Reporting/Filters/KSCrashReportFilterAlert.m'
      end

      filters.subspec 'AppleFmt' do |applefmt|
        applefmt.dependency 'KSCrashAblyFork/Reporting/Filters/Base'
        applefmt.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterAppleFmt.h',
                             'Source/KSCrash/Reporting/Filters/KSCrashReportFilterAppleFmt.m'
      end

      filters.subspec 'Basic' do |basic|
        basic.dependency 'KSCrashAblyFork/Reporting/Filters/Base'
        basic.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterBasic.h',
                             'Source/KSCrash/Reporting/Filters/KSCrashReportFilterBasic.m'
      end

      filters.subspec 'Stringify' do |stringify|
        stringify.dependency 'KSCrashAblyFork/Reporting/Filters/Base'
        stringify.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterStringify.h',
                                 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterStringify.m'
      end

      filters.subspec 'GZip' do |gzip|
        gzip.dependency 'KSCrashAblyFork/Reporting/Filters/Base'
        gzip.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterGZip.h',
                            'Source/KSCrash/Reporting/Filters/KSCrashReportFilterGZip.m'
      end

      filters.subspec 'JSON' do |json|
        json.dependency 'KSCrashAblyFork/Reporting/Filters/Base'
        json.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterJSON.h',
                            'Source/KSCrash/Reporting/Filters/KSCrashReportFilterJSON.m'
      end

      filters.subspec 'Sets' do |sets|
        sets.dependency 'KSCrashAblyFork/Reporting/Filters/Base'
        sets.dependency 'KSCrashAblyFork/Reporting/Filters/AppleFmt'
        sets.dependency 'KSCrashAblyFork/Reporting/Filters/Basic'
        sets.dependency 'KSCrashAblyFork/Reporting/Filters/Stringify'
        sets.dependency 'KSCrashAblyFork/Reporting/Filters/GZip'
        sets.dependency 'KSCrashAblyFork/Reporting/Filters/JSON'

        sets.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterSets.h',
                            'Source/KSCrash/Reporting/Filters/KSCrashReportFilterSets.m'
      end

      filters.subspec 'Tools' do |tools|
        tools.source_files = 'Source/KSCrash/Reporting/Filters/Tools/**/*.{h,m,mm,c,cpp}'
      end

    end

    reporting.subspec 'Tools' do |tools|
      tools.ios.frameworks = 'SystemConfiguration'
      tools.tvos.frameworks = 'SystemConfiguration'
      tools.osx.frameworks = 'SystemConfiguration'
      tools.source_files = 'Source/KSCrash/Reporting/Tools/**/*.{h,m,mm,c,cpp}',
                           'Source/KSCrash/Recording/KSSystemCapabilities.h'
    end

    reporting.subspec 'MessageUI' do |messageui|
    end

    reporting.subspec 'Sinks' do |sinks|
      sinks.ios.frameworks = 'MessageUI'
      sinks.dependency 'KSCrashAblyFork/Reporting/Filters'
      sinks.dependency 'KSCrashAblyFork/Reporting/Tools'
      sinks.source_files = 'Source/KSCrash/Reporting/Sinks/**/*.{h,m,mm,c,cpp}'
    end

  end

  s.subspec 'Installations' do |installations|
    installations.dependency 'KSCrashAblyFork/Recording'
    installations.dependency 'KSCrashAblyFork/Reporting'
    installations.source_files = 'Source/KSCrash/Installations/**/*.{h,m,mm,c,cpp}'
  end

end
