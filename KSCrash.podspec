Pod::Spec.new do |s|
  IOS_DEPLOYMENT_TARGET = '6.0' unless defined? IOS_DEPLOYMENT_TARGET
  s.name         = "KSCrash"
  s.version      = "1.15.27"
  s.summary      = "The Ultimate iOS Crash Reporter"
  s.homepage     = "https://github.com/kstenerud/KSCrash"
  s.license     = { :type => 'KSCrash license agreement', :file => 'LICENSE' }
  s.author       = { "Karl Stenerud" => "kstenerud@gmail.com" }
  s.ios.deployment_target =  IOS_DEPLOYMENT_TARGET
  s.osx.deployment_target =  '10.8'
  s.tvos.deployment_target =  '9.0'
  s.watchos.deployment_target =  '2.0'
  s.source       = { :git => "https://github.com/kstenerud/KSCrash.git", :tag=>s.version.to_s }
  s.frameworks = 'Foundation'
  s.libraries = 'c++', 'z'
  s.xcconfig = { 'GCC_ENABLE_CPP_EXCEPTIONS' => 'YES' }
  s.default_subspecs = 'Installations'

  s.subspec 'Recording' do |recording|
    recording.compiler_flags = '-fno-optimize-sibling-calls'
    recording.source_files   = 'Source/KSCrash/Recording/**/*.{h,m,mm,c,cpp}',
                               'Source/KSCrash/llvm/**/*.{h,m,mm,c,cpp}',
                               'Source/KSCrash/swift/**/*.{h,m,mm,c,cpp,def}',
                               'Source/KSCrash/Reporting/Filters/KSCrashReportFilter.h'
    recording.public_header_files = 'Source/KSCrash/Recording/KSCrash.h',
                                    'Source/KSCrash/Recording/KSCrashC.h',
                                    'Source/KSCrash/Recording/KSCrashReportWriter.h',
                                    'Source/KSCrash/Recording/KSCrashReportFields.h',
                                    'Source/KSCrash/Recording/Monitors/KSCrashMonitorType.h',
                                    'Source/KSCrash/Reporting/Filters/KSCrashReportFilter.h'

    recording.subspec 'Tools' do |tools|
      tools.source_files = 'Source/KSCrash/Recording/Tools/*.h'
      tools.compiler_flags = '-fno-optimize-sibling-calls'
    end
  end

  s.subspec 'Reporting' do |reporting|
    reporting.dependency 'KSCrash/Recording'

    reporting.subspec 'Filters' do |filters|
      filters.subspec 'Base' do |base|
        base.source_files = 'Source/KSCrash/Reporting/Filters/Tools/**/*.{h,m,mm,c,cpp}',
                            'Source/KSCrash/Reporting/Filters/KSCrashReportFilter.h'
        base.public_header_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilter.h'
      end

      filters.subspec 'Alert' do |alert|
        alert.dependency 'KSCrash/Reporting/Filters/Base'
        alert.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterAlert.h',
                             'Source/KSCrash/Reporting/Filters/KSCrashReportFilterAlert.m'
      end

      filters.subspec 'AppleFmt' do |applefmt|
        applefmt.dependency 'KSCrash/Reporting/Filters/Base'
        applefmt.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterAppleFmt.h',
                             'Source/KSCrash/Reporting/Filters/KSCrashReportFilterAppleFmt.m'
      end

      filters.subspec 'Basic' do |basic|
        basic.dependency 'KSCrash/Reporting/Filters/Base'
        basic.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterBasic.h',
                             'Source/KSCrash/Reporting/Filters/KSCrashReportFilterBasic.m'
      end

      filters.subspec 'Stringify' do |stringify|
        stringify.dependency 'KSCrash/Reporting/Filters/Base'
        stringify.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterStringify.h',
                                 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterStringify.m'
      end

      filters.subspec 'GZip' do |gzip|
        gzip.dependency 'KSCrash/Reporting/Filters/Base'
        gzip.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterGZip.h',
                            'Source/KSCrash/Reporting/Filters/KSCrashReportFilterGZip.m'
      end

      filters.subspec 'JSON' do |json|
        json.dependency 'KSCrash/Reporting/Filters/Base'
        json.source_files = 'Source/KSCrash/Reporting/Filters/KSCrashReportFilterJSON.h',
                            'Source/KSCrash/Reporting/Filters/KSCrashReportFilterJSON.m'
      end

      filters.subspec 'Sets' do |sets|
        sets.dependency 'KSCrash/Reporting/Filters/Base'
        sets.dependency 'KSCrash/Reporting/Filters/AppleFmt'
        sets.dependency 'KSCrash/Reporting/Filters/Basic'
        sets.dependency 'KSCrash/Reporting/Filters/Stringify'
        sets.dependency 'KSCrash/Reporting/Filters/GZip'
        sets.dependency 'KSCrash/Reporting/Filters/JSON'

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
      sinks.dependency 'KSCrash/Reporting/Filters'
      sinks.dependency 'KSCrash/Reporting/Tools'
      sinks.source_files = 'Source/KSCrash/Reporting/Sinks/**/*.{h,m,mm,c,cpp}'
    end

  end

  s.subspec 'Installations' do |installations|
    installations.dependency 'KSCrash/Recording'
    installations.dependency 'KSCrash/Reporting'
    installations.source_files = 'Source/KSCrash/Installations/**/*.{h,m,mm,c,cpp}'
  end

  s.subspec 'Core' do |core|
    core.dependency 'KSCrash/Reporting/Filters/Basic'
    core.source_files = 'Source/KSCrash/Installations/KSCrashInstallation.h',
                        'Source/KSCrash/Installations/KSCrashInstallation.m',
                        'Source/KSCrash/Installations/KSCrashInstallation+Private.h',
                        'Source/KSCrash/Reporting/Tools/KSCString.{h,m}'
  end

end
