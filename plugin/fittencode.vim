" plugin name: Fitten Code vim
" plugin version: 0.2.1

if exists("g:loaded_fittencode")
    finish
  endif
let g:loaded_fittencode = 1
let g:accept_just_now = 0

let s:hlgroup = 'FittenSuggestion'
" 新增：追踪当前活跃的虚拟文本信息
let g:active_fitten_virt = {
    \ 'line': -1,
    \ 'col': -1,
    \ 'text': '',
    \ 'total_text': ''
\ }
function! SetSuggestionStyle() abort
    if &t_Co == 256
        hi FittenSuggestion guifg=#808080 ctermfg=244
    else
        hi FittenSuggestion guifg=#808080 ctermfg=8
    endif
    if empty(prop_type_get(s:hlgroup))
        call prop_type_add(s:hlgroup, {'highlight': s:hlgroup})
    endif
endfunction

let g:fitten_auto_completion = 0

function! Fittenlogin(account, password)
    let l:login_url = 'https://fc.fittenlab.cn/codeuser/login'
    let l:json_data = '{"username": "' . a:account . '", "password": "' . a:password . '"}'
    let l:login_command = 'curl -s -X POST -H "Content-Type: application/json" -d ' . shellescape(l:json_data) . ' ' . l:login_url
    let l:response = system(l:login_command)
    let l:login_data = json_decode(l:response)

    if v:shell_error || !has_key(l:login_data, 'code') || l:login_data.code != 200
        echo "Login failed"
        return
    endif

    let l:user_token = l:login_data.data.token

    let l:fico_url = 'https://fc.fittenlab.cn/codeuser/get_ft_token'
    let l:fico_command = 'curl -s -H "Authorization: Bearer ' . l:user_token . '" ' . l:fico_url
    let l:fico_response = system(l:fico_command)
    let l:fico_data = json_decode(l:fico_response)

    if v:shell_error || !has_key(l:fico_data, 'data')
        echo "Login failed"
        return
    endif

    let l:apikey = l:fico_data.data.fico_token
    call writefile([l:apikey], $HOME . '/.vimapikey')

    echo "Login successful, API key saved"
    let g:fitten_login_status = 1
endfunction

command! -nargs=+ Fittenlogin call Fittenlogin(<f-args>)

function! Fittenlogout()
    if filereadable($HOME . '/.vimapikey')
        call delete($HOME . '/.vimapikey')
        echo "Logged out successfully"
    else
        echo "You are already logged out"
    endif
endfunction

command! Fittenlogout call Fittenlogout()


function! CheckLoginStatus()
    if filereadable($HOME . '/.vimapikey')
"        echo "Logged in"
        return 1
    else
"        echo "Not logged in"
        return 0
    endif
endfunction

function! ClearCompletion()
    if exists('b:fitten_suggestion')
        unlet! b:fitten_suggestion
        call prop_remove({'type': s:hlgroup, 'all': v:true})
    endif
	if exists('s:job') && job_status(s:job) == 'run'
		call job_stop(s:job)
        unlet! s:job
	endif
    " 新增：重置虚拟文本追踪变量
    let g:active_fitten_virt = {'line': -1, 'col': -1, 'text': '', 'total_text': ''}
endfunction

function! ClearCompletionByCursorMoved()
    if exists('g:accept_just_now') && g:accept_just_now == 2
        let g:accept_just_now = 1
    endif
    if exists('b:fitten_suggestion')
        call ClearCompletion()
    endif
endfunction

function! CodeCompletion()
    call ClearCompletion()

    let l:filename = substitute(expand('%'), '\\', '/', 'g')

    let l:file_content = join(getline(1, '$'), "\n")
    let l:line_num = line('.')
    let l:col_num = getcurpos()[2]

    let l:prefix = join(getline(1, l:line_num - 1), '\n')
    if !empty(l:prefix)
        let l:prefix = l:prefix . '\n'
    endif
    let l:prefix = l:prefix . strpart(getline(l:line_num), 0, l:col_num - 1)

    let l:suffix = strpart(getline(l:line_num), l:col_num - 1)
    if l:line_num < line('$')
        let l:suffix = l:suffix . '\n' . join(getline(l:line_num + 1, '$'), '\n')
    endif

    let l:prompt = "!FCPREFIX!" . l:prefix . "!FCSUFFIX!" . l:suffix . "!FCMIDDLE!"
    let l:escaped_prompt = escape(l:prompt, '\"')
    " replace \\n to \n
    let l:escaped_prompt = substitute(l:escaped_prompt, '\\\\n', '\\n', 'g')
    " replace \\t to \t
    let l:escaped_prompt = substitute(l:escaped_prompt, '\t', '\\t', 'g')
    let l:token = join(readfile($HOME . '/.vimapikey'), "\n")

    let l:params = '{"inputs": "' . l:escaped_prompt . '", "meta_datas": {"filename": "' . l:filename . '"}}'

    let l:tempfile = tempname()
    call writefile([l:params], l:tempfile)

    let l:server_addr = 'https://fc.fittenlab.cn/codeapi/completion/generate_one_stage/'

    let l:cmd = 'curl -s -X POST -H "Content-Type: application/json" -d @' . l:tempfile . ' "' . l:server_addr . l:token . '?ide=vim&v=0.2.1"'
    "let l:response = system(l:cmd)

    let result = []
    let s:job = job_start(cmd, {
                \ 'out_mode': 'raw',
                \ 'out_cb': { channel, data -> add(result, data) },
                \ 'exit_cb': { job, status -> s:OnExit(result, status, tempfile, col_num) }
                \ })

endfunction

fu s:OnExit(out, status, tempfile, col_num) abort
    call delete(a:tempfile)
    if a:status != 0
        return
    endif

    let l:completion_data = json_decode(join(a:out, "\n"))

    if !has_key(l:completion_data, 'generated_text')
        return
    endif

    let l:generated_text = l:completion_data.generated_text
    let l:generated_text = substitute(l:generated_text, '<.endoftext.>', '', 'g')

    if empty(l:generated_text)
        echow "Fitten Code: No More Suggestions"
        call timer_start(1500, {-> execute('echo ""')})
        return
    endif

    let l:text = split(l:generated_text, "\n", 1)
    if empty(l:text[-1])
        call remove(l:text, -1)
    endif
    let l:text = map(l:text, 'substitute(v:val, "\t", repeat(" ", &ts), "g")')

    let l:is_first_line = v:true
    " 新增：记录完整的补全文本，用于后续匹配
    let g:active_fitten_virt.total_text = join(l:text, "\n")
    let g:active_fitten_virt.line = line('.')
    let g:active_fitten_virt.col = a:col_num
    let g:active_fitten_virt.text = g:active_fitten_virt.total_text
    for line in text
        if empty(line)
            let line = " "
        endif
        if l:is_first_line is v:true
            let l:is_first_line = v:false
            call prop_add(line('.'), a:col_num, {'type': s:hlgroup, 'text': line})
        else
            call prop_add(line('.'), 0, {'type': s:hlgroup, 'text_align': 'below', 'text': line})
        endif
    endfor

    let b:fitten_suggestion = l:generated_text
endf

" 新增：处理输入与虚拟文本的匹配逻辑
function! HandleFittenVirtMatch() abort
    " 无活跃虚拟文本或无补全内容时直接返回
    if !exists('g:active_fitten_virt') || g:active_fitten_virt.line == -1 || !exists('b:fitten_suggestion')
        return
    endif
    let l:virt_line = g:active_fitten_virt.line
    let l:virt_col = g:active_fitten_virt.col
    let l:total_virt_text = g:active_fitten_virt.total_text
    " 光标不在虚拟文本所在行，直接清除
    if line('.') != l:virt_line
        call ClearCompletion()
        let g:active_fitten_virt = {'line': -1, 'col': -1, 'text': '', 'total_text': ''}
        return
    endif
    " 获取用户输入的文本（虚拟文本起始列到当前光标前）
    let l:current_col = getcurpos()[2]
    if l:current_col < l:virt_col
        call ClearCompletion()
        let g:active_fitten_virt = {'line': -1, 'col': -1, 'text': '', 'total_text': ''}
        return
    endif
    let l:input_text = strpart(getline('.') , l:virt_col - 1, l:current_col - l:virt_col)
    let l:input_len = len(l:input_text)
    let l:virt_len = len(l:total_virt_text)
    " 输入长度超过虚拟文本长度，直接清除
    if l:input_len > l:virt_len
        call ClearCompletion()
        let g:active_fitten_virt = {'line': -1, 'col': -1, 'text': '', 'total_text': ''}
        return
    endif
    " 提取虚拟文本前缀进行匹配（区分大小写）
    let l:virt_prefix = strpart(l:total_virt_text, 0, l:input_len)
    if l:input_text ==# l:virt_prefix
        " 匹配成功：清除旧虚拟文本，显示剩余部分
        let l:remaining_text = strpart(l:total_virt_text, l:input_len)
        if empty(l:remaining_text)
            call ClearCompletion()
            let g:active_fitten_virt = {'line': -1, 'col': -1, 'text': '', 'total_text': ''}
            return
        endif
        call ClearCompletion()
        " 重新创建剩余部分的虚拟文本
        let l:text_lines = split(l:remaining_text, "\n", 1)
        let l:is_first_line = v:true
        for line in l:text_lines
            if empty(line)
                let line = " "
            endif
            if l:is_first_line
                call prop_add(line('.'), l:current_col, {'type': s:hlgroup, 'text': line})
                let l:is_first_line = v:false
            else
                call prop_add(line('.'), 0, {'type': s:hlgroup, 'text_align': 'below', 'text': line})
            endif
        endfor
        " 更新虚拟文本追踪信息
        let g:active_fitten_virt.text = l:remaining_text
        let g:active_fitten_virt.col = l:current_col
        let b:fitten_suggestion = l:remaining_text
    else
        " 匹配失败：清除虚拟文本
        call ClearCompletion()
        let g:active_fitten_virt = {'line': -1, 'col': -1, 'text': '', 'total_text': ''}
    endif
endfunction

function! CodeAutoCompletion()
    if g:fitten_login_status == 0
        return ""
    endif
    if !exists('g:accept_just_now') || g:accept_just_now == 1 || g:accept_just_now == 2
        let g:accept_just_now = g:accept_just_now - 1
        return ""
    endif
    if col('.') == col('$')
        call CodeCompletion()
        return ""
    endif
    if empty(substitute(getline('.')[col('.') - 1:], '\s', '', 'g'))
        call CodeCompletion()
        return ""
    endif
endfunction

function! FittenAcceptMain()
    echo "Accept"
    let default = pumvisible() ? "\<C-N>" : "\t"

    if mode() !~# '^[iR]' || !exists('b:fitten_suggestion')
        return g:fitten_accept_key == "\t" ? default : g:fitten_accept_key
    endif

    let l:text = b:fitten_suggestion

    call ClearCompletion()

    return l:text
endfunction

function! FittenInsert(text, is_first_line) abort
    if a:is_first_line == v:false
        call append('.', '')
        let l:line = line('.') + 1
    else
        let l:line = line('.')
    endif
    let l:col = col('.')
    let l:oldline = getline(l:line)
    let l:prefix = strpart(l:oldline, 0, l:col-1)
    let l:suffix = strpart(l:oldline, l:col-1)
    let l:newline = l:prefix . a:text . l:suffix
    call setline(l:line, l:newline)
    call cursor(l:line, l:col + len(a:text))
endfunction

function FittenAccept()
    let g:accept_just_now = 2
    let l:accept = FittenAcceptMain()
    let l:accept_lines = split(l:accept, "\n", v:true)

    let l:is_first_line = v:true
    for line in l:accept_lines
        call FittenInsert(line, l:is_first_line)
        let l:is_first_line = v:false
    endfor

    return ""
endfunction

function! FittenAcceptable()
    return (mode() !~# '^[iR]' || !exists('b:fitten_suggestion')) ? 0 : 1
endfunction

if !exists('g:fitten_trigger')
    let g:fitten_trigger = "\<C-l>"
endif
if !exists('g:fitten_accept_key')
    let g:fitten_accept_key = "\<Tab>"
endif
if !exists('g:fitten_login_status')
    let g:fitten_login_status = CheckLoginStatus()
endif
function! FittenMapping()
    execute "inoremap" keytrans(g:fitten_trigger) '<Cmd>call CodeCompletion()<CR>'
    if g:fitten_accept_key isnot v:none
        execute 'inoremap' keytrans(g:fitten_accept_key) '<Cmd>call FittenAccept()<CR>'
    endif
endfunction

command! FittenAutoCompletionOn let g:fitten_auto_completion = 1 | echo 'Fitten Code Auto Completion Enabled'

command! FittenAutoCompletionOff let g:fitten_auto_completion = 0 | echo 'Fitten Code Auto Completion Disabled'

augroup fittencode
    autocmd!
    autocmd CursorMovedI * call ClearCompletionByCursorMoved()
    autocmd InsertLeave  * call ClearCompletion()
    autocmd BufLeave     * call ClearCompletion()
    autocmd ColorScheme,VimEnter * call SetSuggestionStyle()
    " Map tab using vim enter so it occurs after all other sourcing.
    autocmd VimEnter             * call FittenMapping()
    set updatetime=1500
    autocmd CursorHoldI  * if g:fitten_auto_completion == 1 | call CodeAutoCompletion() | endif
    " 新增：插入字符时触发匹配逻辑
    autocmd InsertCharPre * call HandleFittenVirtMatch()
    " 新增：插入模式文本变化时触发（处理删除、粘贴等场景）
    autocmd TextChangedI * call HandleFittenVirtMatch()
augroup END
