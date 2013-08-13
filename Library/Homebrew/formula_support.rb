require 'download_strategy'
require 'checksum'
require 'version'
require 'resource'

FormulaConflict = Struct.new(:name, :reason)

class SoftwareSpec
  attr_reader :resources, :main_resource

  def initialize url=nil, version=nil
    @main_resource = Resource.new('main', url, version)
    @resources = {'main' => @main_resource}
  end

  # The methods that follow are used in the block-form DSL spec methods
  # Proxy some methods to the main resource
  ([:url, :mirror, :specs, :using, :checksum, :version] + Checksum::TYPES).each do |meth|
    class_eval <<-EOS, __FILE__, __LINE__ + 1
      def #{meth} *args
        @main_resource.#{meth}(*args)
      end
    EOS
  end

  # Define a named resource
  def resource res_name, &block
    raise DuplicateResourceError.new(res_name) if resources.has_key?(res_name)
    res = Resource.new(res_name)
    res.instance_eval(&block)
    resources[res_name] = res
  end
end

class HeadSoftwareSpec < SoftwareSpec
  def initialize url=nil, version=Version.new(:HEAD)
    super
  end

  def verify_download_integrity fn
    return
  end
end

class Bottle < SoftwareSpec
  attr_rw :root_url, :prefix, :cellar, :revision

  def initialize
    super
    @revision = 0
    @prefix = '/usr/local'
    @cellar = '/usr/local/Cellar'
  end

  def url= val
    @main_resource.url = val
  end

  # Checksum methods in the DSL's bottle block optionally take
  # a Hash, which indicates the platform the checksum applies on.
  Checksum::TYPES.each do |cksum|
    class_eval <<-EOS, __FILE__, __LINE__ + 1
      def #{cksum}(val=nil)
        return @#{cksum} if val.nil?
        @#{cksum} ||= Hash.new
        case val
        when Hash
          key, value = val.shift
          @#{cksum}[value] = Checksum.new(:#{cksum}, key)
        end

        if @#{cksum}.has_key? bottle_tag
          @main_resource.checksum = @#{cksum}[bottle_tag]
        end
      end
    EOS
  end
end


# Used to annotate formulae that duplicate OS X provided software
# or cause conflicts when linked in.
class KegOnlyReason
  attr_reader :reason, :explanation

  def initialize reason, explanation=nil
    @reason = reason
    @explanation = explanation
    @valid = case @reason
      when :provided_pre_mountain_lion then MacOS.version < :mountain_lion
      else true
      end
  end

  def valid?
    @valid
  end

  def to_s
    case @reason
    when :provided_by_osx then <<-EOS.undent
      Mac OS X already provides this software and installing another version in
      parallel can cause all kinds of trouble.

      #{@explanation}
      EOS
    when :provided_pre_mountain_lion then <<-EOS.undent
      Mac OS X already provides this software in versions before Mountain Lion.

      #{@explanation}
      EOS
    else
      @reason
    end.strip
  end
end
