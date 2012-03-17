;*****************start of the kernel code***************
[org 0x000]
[bits 16]

[SEGMENT .text]

;START #####################################################
    mov ax, 0x0100			;location where kernel is loaded
    mov ds, ax
    mov es, ax
    
    cli
    mov ss, ax				;stack segment
    mov sp, 0xFFFF			;stack pointer at 64k limit
    sti

    push dx
    push es
    xor ax, ax
    mov es, ax
    cli
    mov word [es:0x21*4], _int0x21	; setup interrupt service
    mov [es:0x21*4+2], cs
    sti
    pop es
    pop dx

    mov si, strWelcomeMsg   ; load message
    mov al, 0x01            ; request sub-service 0x01
    int 0x21

	call _shell				; call the shell
    
    int 0x19                ; reboot
;END #######################################################

_int0x21:
    _int0x21_ser0x01:       ;service 0x01
    cmp al, 0x01            ;see if service 0x01 wanted
    jne _int0x21_end        ;goto next check (now it is end)
    
	_int0x21_ser0x01_start:
    lodsb                   ; load next character
    or  al, al              ; test for NUL character
    jz  _int0x21_ser0x01_end
    mov ah, 0x0E            ; BIOS teletype
    mov bh, 0x00            ; display page 0
    mov bl, 0x07            ; text attribute
    int 0x10                ; invoke BIOS
    jmp _int0x21_ser0x01_start
    _int0x21_ser0x01_end:
    jmp _int0x21_end

    _int0x21_end:
    iret

_shell:
	_shell_begin:
	;move to next line
	call _display_endl

	;display prompt
	call _display_prompt

	;get user command
	call _get_command
	
	;split command into components
	call _split_cmd

	;check command & perform action

	; empty command
	_cmd_none:		
	mov si, strCmd0
	cmp BYTE [si], 0x00
	jne	_cmd_ver		;next command
	jmp _cmd_done
	
	; display version
	_cmd_ver:		
	mov si, strCmd0
	mov di, cmdVer
	mov cx, 4
	repe	cmpsb
	jne	_cmd_info		;next command
	
	call _display_endl
	mov si, strOsName		;display version
	mov al, 0x01
    int 0x21
	call _display_space
	mov si, txtVersion		;display version
	mov al, 0x01
    int 0x21
	call _display_space

	mov si, strMajorVer		
	mov al, 0x01
    int 0x21
	mov si, strMinorVer
	mov al, 0x01
    int 0x21
	jmp _cmd_done

	_cmd_info:			;display hardware details
	mov si, strCmd0
	mov di, cmdInfo
	mov cx, 4
	repe	cmpsb
	jne _cmd_exit	;display keyboard status


	call _display_endl
	mov si, strHard
	mov al, 0x01
	int 0x21
	call _display_endl

	call _display_endl
	mov si, strBasic
	mov al, 0x01
	int 0x21
	call _display_endl
	call _display_endl

	call _display_cpu_vendor	;display CPU vendor
	call _display_processor_brand	;display processor brand
	call _display_ram_info		;display ram size
	call _dispaly_num_of_hDD	;display num of HDD
	call _display_serial_ports	;display number of serial ports
	call _display_parallel_ports    ;display number of parallel ports

	call _display_endl
	call _display_endl
	mov si, strIndicators
	mov al, 0x01
	int 0x21
	call _display_endl
	call _display_endl	

	call _numlock_state
	call _capslock_state

	call _display_endl
	mov si, strWExitInfo
	mov al, 0x01
	int 0x21

	jmp _cmd_done

	; exit shell



	_cmd_exit:		
	mov si, strCmd0
	mov di, cmdExit
	mov cx, 5
	repe	cmpsb
	jne	_cmd_unknown		;next command

	je _shell_end			;exit from shell

	_cmd_unknown:
	call _display_endl
	mov si, msgUnknownCmd		;unknown command
	mov al, 0x01
    int 0x21

	_cmd_done:

	;call _display_endl
	jmp _shell_begin
	
	_shell_end:
	ret

_get_command:
	;initiate count
	mov BYTE [cmdChrCnt], 0x00
	mov di, strUserCmd

	_get_cmd_start:
	mov ah, 0x10		;get character
	int 0x16

	cmp al, 0x00		;check if extended key
	je _extended_key
	cmp al, 0xE0		;check if new extended key
	je _extended_key

	cmp al, 0x08		;check if backspace pressed
	je _backspace_key

	cmp al, 0x0D		;check if Enter pressed
	je _enter_key

	mov bh, [cmdMaxLen]		;check if maxlen reached
	mov bl, [cmdChrCnt]
	cmp bh, bl
	je	_get_cmd_start

	;add char to buffer, display it and start again
	mov [di], al			;add char to buffer
	inc di					;increment buffer pointer
	inc BYTE [cmdChrCnt]	;inc count

	mov ah, 0x0E			;display character
	mov bl, 0x07
	int 0x10
	jmp	_get_cmd_start

	_extended_key:			;extended key - do nothing now
	jmp _get_cmd_start

	_backspace_key:
	mov bh, 0x00			;check if count = 0
	mov bl, [cmdChrCnt]
	cmp bh, bl
	je	_get_cmd_start		;yes, do nothing
	
	dec BYTE [cmdChrCnt]	;dec count
	dec di

	;check if beginning of line
	mov	ah, 0x03		;read cursor position
	mov bh, 0x00
	int 0x10

	cmp dl, 0x00
	jne	_move_back
	dec dh
	mov dl, 79
	mov ah, 0x02
	int 0x10

	mov ah, 0x09		; display without moving cursor
	mov al, ' '
    mov bh, 0x00
    mov bl, 0x07
	mov cx, 1			; times to display
    int 0x10
	jmp _get_cmd_start

	_move_back:
	mov ah, 0x0E		; BIOS teletype acts on backspace!
    mov bh, 0x00
    mov bl, 0x07
    int 0x10
	mov ah, 0x09		; display without moving cursor
	mov al, ' '
    mov bh, 0x00
    mov bl, 0x07
	mov cx, 1			; times to display
    int 0x10
	jmp _get_cmd_start

	_enter_key:
	mov BYTE [di], 0x00
	ret

_split_cmd:
	;adjust si/di
	mov si, strUserCmd
	;mov di, strCmd0

	;move blanks
	_split_mb0_start:
	cmp BYTE [si], 0x20
	je _split_mb0_nb
	jmp _split_mb0_end

	_split_mb0_nb:
	inc si
	jmp _split_mb0_start

	_split_mb0_end:
	mov di, strCmd0

	_split_1_start:			;get first string
	cmp BYTE [si], 0x20
	je _split_1_end
	cmp BYTE [si], 0x00
	je _split_1_end
	mov al, [si]
	mov [di], al
	inc si
	inc di
	jmp _split_1_start

	_split_1_end:
	mov BYTE [di], 0x00

	;move blanks
	_split_mb1_start:
	cmp BYTE [si], 0x20
	je _split_mb1_nb
	jmp _split_mb1_end

	_split_mb1_nb:
	inc si
	jmp _split_mb1_start

	_split_mb1_end:
	mov di, strCmd1

	_split_2_start:			;get second string
	cmp BYTE [si], 0x20
	je _split_2_end
	cmp BYTE [si], 0x00
	je _split_2_end
	mov al, [si]
	mov [di], al
	inc si
	inc di
	jmp _split_2_start

	_split_2_end:
	mov BYTE [di], 0x00

	;move blanks
	_split_mb2_start:
	cmp BYTE [si], 0x20
	je _split_mb2_nb
	jmp _split_mb2_end

	_split_mb2_nb:
	inc si
	jmp _split_mb2_start

	_split_mb2_end:
	mov di, strCmd2

	_split_3_start:			;get third string
	cmp BYTE [si], 0x20
	je _split_3_end
	cmp BYTE [si], 0x00
	je _split_3_end
	mov al, [si]
	mov [di], al
	inc si
	inc di
	jmp _split_3_start

	_split_3_end:
	mov BYTE [di], 0x00

	;move blanks
	_split_mb3_start:
	cmp BYTE [si], 0x20
	je _split_mb3_nb
	jmp _split_mb3_end

	_split_mb3_nb:
	inc si
	jmp _split_mb3_start

	_split_mb3_end:
	mov di, strCmd3

	_split_4_start:			;get fourth string
	cmp BYTE [si], 0x20
	je _split_4_end
	cmp BYTE [si], 0x00
	je _split_4_end
	mov al, [si]
	mov [di], al
	inc si
	inc di
	jmp _split_4_start

	_split_4_end:
	mov BYTE [di], 0x00

	;move blanks
	_split_mb4_start:
	cmp BYTE [si], 0x20
	je _split_mb4_nb
	jmp _split_mb4_end

	_split_mb4_nb:
	inc si
	jmp _split_mb4_start

	_split_mb4_end:
	mov di, strCmd4

	_split_5_start:			;get last string
	cmp BYTE [si], 0x20
	je _split_5_end
	cmp BYTE [si], 0x00
	je _split_5_end
	mov al, [si]
	mov [di], al
	inc si
	inc di
	jmp _split_5_start

	_split_5_end:
	mov BYTE [di], 0x00

	ret



_display_ram_info:			;display ram size, total memory

	call _display_base_memory	

	mov si, strMemo	
	mov al, 0x01
	int 0x21

	mov ax, 0xe801			;display extended memory 
	int 0x15

	shr ax, 10			;memory 1mb to 16 mb in KB
	shr bx, 4			;memory > 16mb in 64 KB blocks 
	add ax, bx
	mov dx, ax
	call _hex2dec

	call _display_space
	mov si, strMb
	mov al, 0x01
	int 0x21

	call _display_endl
	ret

_display_base_memory:			;display base memory <1 mb

	mov si, strBaMemo	
	mov al, 0x01
	int 0x21

	int 0x12
	mov dx, ax
	call _hex2dec
	call _display_space

	mov si, strKb
	mov al, 0x01
	int 0x21
	call _display_endl
	ret

_display_processor_brand:		;display porcessor brand ascii string stored in eax,ebx,ecx,edx while calling eax=80000002h,80000003h,80000004h cpuid

	mov si, strCpuBrand	
	mov al, 0x01
	int 0x21

	mov eax, 80000002h
	cpuid
	mov [strCpuId], eax	
	mov [strCpuId+4], ebx	
	mov [strCpuId+8], ecx	
	mov [strCpuId+12], edx	
	mov si, strCpuId
	mov al, 0x01
	int 0x21

	mov eax, 80000003h
	cpuid
	mov [strCpuId], eax	
	mov [strCpuId+4], ebx	
	mov [strCpuId+8], ecx	
	mov [strCpuId+12], edx	
	mov si, strCpuId
	mov al, 0x01
	int 0x21

	mov eax, 80000004h
	cpuid
	mov [strCpuId], eax	
	mov [strCpuId+4], ebx	
	mov [strCpuId+8], ecx	
	mov [strCpuId+12], edx	
	mov si, strCpuId
	mov al, 0x01
	int 0x21
	call _display_endl
	ret

_display_cpu_vendor:			;display cpu vendor ascii string stored in ebx,edx,ecx while calling eax=0 cpuid

	mov si, strCpu	
	mov al, 0x01
	int 0x21

	mov eax, 0
	cpuid
	mov [strCpuVen], ebx
	mov [strCpuVen+4], edx
	mov [strCpuVen+8], ecx
	mov si, strCpuVen
	mov al, 0x01
	int 0x21

	call _display_endl
	ret

_dispaly_num_of_hDD:			;number of hard disk drives attached

	mov si, strHDD
	mov al, 0x01
	int 0x21

	push es
	mov ax, 0x40
	mov es, ax
	mov ax, [es:75h]
	add ax, 30h
	mov ah, 0x0e
	int 0x10
	pop es
	call _display_endl
	ret


_display_serial_ports:			;display number of serial ports

	mov si, strSerial
	mov al, 0x01
	int 0x21

	push es
	mov ax, 0x40
	mov es, ax
	mov ax, [es:10h]
	and ax, 0xe00
	shr ax, 9
	add ax, 30h
	mov ah, 0x0e
	int 0x10
	call _display_endl
	pop es
	ret

_display_parallel_ports:		;display number of parallel ports
	
	mov si, strParallel
	mov al, 0x01
	int 0x21

	push es
	mov ax, 0x40
	mov es, ax
	mov ax, [es:10h]
	and ax, 0xffffc000
	shr ax, 14
	add ax, 30h
	mov ah, 0x0e
	int 0x10
	pop es
	ret

_numlock_state:				;state whether numlock enabled or disabled

	mov si, strNumlock
	mov al, 0x01
	int 0x21

	push es
	mov ax, 0x40
	mov es, ax
	mov ax, [es:17h]
	and ax, 20h
	shr ax, 5
	pop es
	
	cmp ax, 0
	je _state_off

	call _state_on
	ret

_capslock_state:			;state whether capslock enabled or disabled

	mov si, strCapslock
	mov al, 0x01
	int 0x21

	push es
	mov ax, 0x40
	mov es, ax
	mov ax, [es:17h]
	and ax, 40h
	shr ax, 6
	pop es
	
	cmp ax, 0
	je _state_off

	call _state_on
	ret

_state_off:

	mov si, strStateOff
	mov al, 0x01
	int 0x21
	call _display_endl
	ret

_state_on:

	mov si, strStateOn
	mov al, 0x01
	int 0x21
	call _display_endl
	ret
	

_display_space:
	mov ah, 0x0E                            ; BIOS teletype
	mov al, 0x20
    mov bh, 0x00                            ; display page 0
    mov bl, 0x07                            ; text attribute
    int 0x10                                ; invoke BIOS
	ret

_display_endl:
	mov ah, 0x0E		; BIOS teletype acts on newline!
    mov al, 0x0D
	mov bh, 0x00
    mov bl, 0x07
    int 0x10
	mov ah, 0x0E		; BIOS teletype acts on linefeed!
    mov al, 0x0A
	mov bh, 0x00
    mov bl, 0x07
    int 0x10
	ret



_hex2dec:

	push ax                  ; save AX
	push bx                  ; save CX
	push cx                  ; save DX
	push si                  ; save SI
	mov ax,dx                ; copy number into AX
	mov si,10                ; SI will be the divisor
	xor cx,cx                ; clean up the CX

	_non_zero:

	xor dx,dx                ; clean up the DX
	div si                   ; divide by 10
	push dx                  ; push number onto the stack
	inc cx                   ; increment CX to do it more times
	or ax,ax                 ; end of the number?
	jne _non_zero		; if not go to _non_zero

	_write_digits:

	pop dx                   ; get the digit off DX
	add dl,0x30               ; add 30 to get the ASCII value
	call _print_char          ; print 
	loop _write_digits        ; keep going till cx == 0

	pop si                   ; restore SI
	pop cx                   ; restore DX
	pop bx                   ; restore CX
	pop ax                   ; restore AX
	ret 

                     
_print_char:
	push ax                  ; save that AX register
	mov al, dl
        mov ah, 0x0E            ; BIOS teletype acts on newline!
        mov bh, 0x00
        mov bl, 0x07
        int 0x10

	pop ax                   ; restore that AX register
	ret


_display_prompt:
	mov si, strPrompt
	mov al, 0x01
	int 0x21
	ret

[SEGMENT .data]
    	strWelcomeMsg   	db  	"WELCOME -JOSH Vesion 0.03.1", 0x00
	strPrompt		db	"$:/", 0x00
	cmdMaxLen		db	255			;maximum length of commands

	strOsName		db	"Josh", 0x00		;OS details
	strMajorVer		db	"0", 0x00
	strMinorVer		db	".03.1", 0x00
	strHard			db	"---------------------------------System Information-----------------------------", 0x00
	strMb			db	"MB", 0x00
	strKb			db	"KB", 0x00
	strBaMemo		db	"   Base Memory     :            ", 0x00
	strMemo			db	"   Memory          :            ", 0x00
	strSerial		db	"   Serial Ports    :            ", 0x00
	strParallel		db	"   Parallel Ports  :            ", 0x00
	strCpu			db	"   CPU Vendor      :            ", 0x00
	strCpuBrand		db	"   CPU Brand       :            ", 0x00
	strWExitInfo    	db  	"--------------------------------------------------------------------------------", 0x00
	strNumlock		db	"   Num Lock        :            ", 0x00
	strCapslock		db	"   Caps Lock       :            ", 0x00
	strHDD			db	"   HD Drives       :            ", 0x00
	strBasic		db	"Basic Information", 0x00
	strIndicators		db	"System Tray Indicators", 0x00
	strStateOn		db	"Enabled", 0x00
	strStateOff		db	"Disabled", 0x00


	cmdVer			db	"ver", 0x00		; internal commands
	cmdExit			db	"exit", 0x00	
	cmdInfo			db	"info", 0x00		;display memory size

	txtVersion		db	"Version", 0x00	;messages and other strings
	msgUnknownCmd	db	"Unknown command or bad file name!", 0x00

[SEGMENT .bss]
	strUserCmd	resb	256		;buffer for user commands
	strCpuId	resb	128		;buffer for cpu brand string
	strCpuVen	resb	96		;buffer for cpu vendor string
	cmdChrCnt	resb	1		;count of characters
	strCmd0		resb	256		;buffers for the command components
	strCmd1		resb	256
	strCmd2		resb	256
	strCmd3		resb	256
	strCmd4		resb	256

;********************end of the kernel code********************
