" Script Name: mark.vim
" Description: Highlight several words in different colors simultaneously. 
"
" Copyright:   (C) 2005-2008 by Yuheng Xie
"              (C) 2008-2009 by Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'. 
"
" Maintainer:  Ingo Karkat <ingo@karkat.de> 
"
" Dependencies:
"  - SearchSpecial.vim autoload script (optional, for improved search messages). 
"
" Version:     2.2.0
" Changes:
" 02-Jul-2009, Ingo Karkat
" - Split off functions into autoload script. 

let s:current_mark_position = ''

"- functions ------------------------------------------------------------------
function! s:EscapeText( text )
	return substitute( escape(a:text, '\' . '^$.*[~'), "\n", '\\n', 'ge' )
endfunction
" Mark the current word, like the built-in star command. 
" If the cursor is on an existing mark, remove it. 
function! mark#MarkCurrentWord()
	let l:regexp = mark#CurrentMark()
	if empty(l:regexp)
		let l:cword = expand("<cword>")

		" The star command only creates a \<whole word\> search pattern if the
		" <cword> actually only consists of keyword characters. 
		if l:cword =~# '^\k\+$'
			let l:regexp = '\<' . s:EscapeText(l:cword) . '\>'
		elseif l:cword != ''
			let l:regexp = s:EscapeText(l:cword)
		endif
	endif

	if ! empty(l:regexp)
		call mark#DoMark(l:regexp)
	endif
endfunction

function! s:GetVisualSelection()
	let save_a = @a
	silent normal! gv"ay
	let res = @a
	let @a = save_a
	return res
endfunction

function! mark#GetVisualSelectionEscaped(flags)
	" flags:
	"  "e" \  -> \\  
	"  "n" \n -> \\n  for multi-lines visual selection
	"  "N" \n removed
	"  "V" \V added   for marking plain ^, $, etc.
	let result = s:GetVisualSelection()
	let i = 0
	while i < strlen(a:flags)
		if a:flags[i] ==# "e"
			let result = escape(result, '\')
		elseif a:flags[i] ==# "n"
			let result = substitute(result, '\n', '\\n', 'g')
		elseif a:flags[i] ==# "N"
			let result = substitute(result, '\n', '', 'g')
		elseif a:flags[i] ==# "V"
			let result = '\V' . result
		endif
		let i = i + 1
	endwhile
	return result
endfunction

" Manually input a regular expression. 
function! mark#MarkRegex(...) " MarkRegex(regexp)
	let regexp = ""
	if a:0 > 0
		let regexp = a:1
	endif
	call inputsave()
	let r = input("@", regexp)
	call inputrestore()
	if r != ""
		call mark#DoMark(r)
	endif
endfunction

function! s:Cycle( ... )
	let l:currentCycle = g:mwCycle
	let l:newCycle = (a:0 ? a:1 : g:mwCycle) + 1
	let g:mwCycle = (l:newCycle < g:mwCycleMax ? l:newCycle : 0)
	return l:currentCycle
endfunction

" Set / clear matches in the current window. 
function! s:MarkMatch( indices, expr )
	for l:index in a:indices
		if w:mwMatch[l:index] > 0
			silent! call matchdelete(w:mwMatch[l:index])
			let w:mwMatch[l:index] = 0
		endif
	endfor

	if ! empty(a:expr)
		" Make the match according to the 'ignorecase' setting, like the star command. 
		" (But honor an explicit case-sensitive regexp via the /\C/ atom.) 
		let l:expr = ((&ignorecase && a:expr !~# '\\\@<!\\C') ? '\c' . a:expr : a:expr)

		let w:mwMatch[a:indices[0]] = matchadd('MarkWord' . (a:indices[0] + 1), l:expr, -10)
	endif
endfunction
" Set / clear matches in all windows. 
function! s:MarkScope( indices, expr )
	let l:currentWinNr = winnr()

	" By entering a window, its height is potentially increased from 0 to 1 (the
	" minimum for the current window). To avoid any modification, save the window
	" sizes and restore them after visiting all windows. 
	let l:originalWindowLayout = winrestcmd() 

	noautocmd windo call s:MarkMatch(a:indices, a:expr)
	execute l:currentWinNr . 'wincmd w'
	silent! execute l:originalWindowLayout
endfunction
" Update matches in all windows. 
function! mark#UpdateScope()
	let l:currentWinNr = winnr()

	" By entering a window, its height is potentially increased from 0 to 1 (the
	" minimum for the current window). To avoid any modification, save the window
	" sizes and restore them after visiting all windows. 
	let l:originalWindowLayout = winrestcmd() 

	noautocmd windo call mark#UpdateMark()
	execute l:currentWinNr . 'wincmd w'
	silent! execute l:originalWindowLayout
endfunction
" Mark or unmark a regular expression. 
function! mark#DoMark(...) " DoMark(regexp)
	let regexp = (a:0 ? a:1 : '')

	" clear all marks if regexp is null
	if empty(regexp)
		let i = 0
		let indices = []
		while i < g:mwCycleMax
			if !empty(g:mwWord[i])
				let g:mwWord[i] = ''
				call add(indices, i)
			endif
			let i += 1
		endwhile
		let g:mwLastSearched = ""
		call s:MarkScope(l:indices, '')
		return
	endif

	" clear the mark if it has been marked
	let i = 0
	while i < g:mwCycleMax
		if regexp == g:mwWord[i]
			if g:mwLastSearched == g:mwWord[i]
				let g:mwLastSearched = ''
			endif
			let g:mwWord[i] = ''
			call s:MarkScope([i], '')
			return
		endif
		let i += 1
	endwhile

	" add to history
	if stridx(g:mwHistAdd, "/") >= 0
		call histadd("/", regexp)
	endif
	if stridx(g:mwHistAdd, "@") >= 0
		call histadd("@", regexp)
	endif

	" choose an unused mark group
	let i = 0
	while i < g:mwCycleMax
		if empty(g:mwWord[i])
			let g:mwWord[i] = regexp
			call s:Cycle(i)
			call s:MarkScope([i], regexp)
			return
		endif
		let i += 1
	endwhile

	" choose a mark group by cycle
	let i = s:Cycle()
	if g:mwLastSearched == g:mwWord[i]
		let g:mwLastSearched = ''
	endif
	let g:mwWord[i] = regexp
	call s:MarkScope([i], regexp)
endfunction
" Initialize mark colors in a (new) window. 
function! mark#UpdateMark()
	if ! exists('w:mwMatch')
		let w:mwMatch = repeat([0], g:mwCycleMax)
	endif

	let i = 0
	while i < g:mwCycleMax
		if empty(g:mwWord[i])
			call s:MarkMatch([i], '')
		else
			call s:MarkMatch([i], g:mwWord[i])
		endif
		let i += 1
	endwhile
endfunction

" Return the mark string under the cursor; multi-lines marks not supported. 
function! mark#CurrentMark()
	let line = getline(".")
	let i = 0
	while i < g:mwCycleMax
		if !empty(g:mwWord[i])
			let start = 0
			while start >= 0 && start < strlen(line) && start < col(".")
				let b = match(line, g:mwWord[i], start)
				let e = matchend(line, g:mwWord[i], start)
				if b < col(".") && col(".") <= e
					let s:current_mark_position = line(".") . "_" . b
					return g:mwWord[i]
				endif
				let start = e
			endwhile
		endif
		let i += 1
	endwhile
	return ""
endfunction

" Search current mark. 
function! mark#SearchCurrentMark(...) " SearchCurrentMark(flags)
	let flags = ""
	let l:isFound = 0
	if a:0 > 0
		let flags = a:1
	endif
	let w = mark#CurrentMark()
	if w != ""
		let p = s:current_mark_position
		let l:isFound = s:Search(w, flags, (w ==# g:mwLastSearched ? 'same-mark' : 'new-mark'))
		call mark#CurrentMark()
		if p == s:current_mark_position
			let l:isFound = search(w, flags)
		endif
		let g:mwLastSearched = w
	else
		if g:mwLastSearched != ""
			let l:isFound = s:Search(g:mwLastSearched, flags, 'same-mark')
		else
			call mark#SearchAnyMark(flags)
			let g:mwLastSearched = mark#CurrentMark()
		endif
	endif
	if l:isFound
		normal! zv
	endif
endfunction

silent! call SearchSpecial#DoesNotExist()	" Execute a function to force autoload.  
if exists('*SearchSpecial#WrapMessage')
	function! s:WrapMessage( searchType, searchPattern, isBackward )
		redraw
		call SearchSpecial#WrapMessage(a:searchType, a:searchPattern, a:isBackward)
	endfunction
	function! s:ErrorMessage( searchType, searchPattern )
		call SearchSpecial#ErrorMessage(a:searchPattern, a:searchType . ' not found')
	endfunction
	function! s:EchoSearchPattern( searchType, searchPattern, isBackward )
		call SearchSpecial#EchoSearchPattern(a:searchType, a:searchPattern, a:isBackward)
	endfunction
else
	function! s:Trim( message )
		" Limit length to avoid "Hit ENTER" prompt. 
		return strpart(a:message, 0, (&columns / 2)) . (len(a:message) > (&columns / 2) ? "..." : "")
	endfunction
	function! s:WrapMessage( searchType, searchPattern, isBackward )
		redraw
		let v:warningmsg = a:searchType . ' search hit ' . (a:isBackward ? 'TOP' : 'BOTTOM') . ', continuing at ' . (a:isBackward ? 'BOTTOM' : 'TOP')
		echohl WarningMsg
		echo s:Trim(v:warningmsg)
		echohl None
	endfunction
	function! s:ErrorMessage( searchType, searchPattern )
		let v:errmsg = a:searchType . ' not found: ' . a:searchPattern
		echohl ErrorMsg
		echomsg v:errmsg
		echohl None
	endfunction
	function! s:EchoSearchPattern( searchType, searchPattern, isBackward )
		let l:message = (a:isBackward ? '?' : '/') .  a:searchPattern
		echohl SearchSpecialSearchType
		echo a:searchType
		echohl None
		echon s:Trim(l:message)
	endfunction
endif

" Wrapper around search() with additonal search and error messages and "wrapscan" warning. 
function! s:Search( pattern, flags, searchType )
	let l:isBackward = (stridx(a:flags, 'b') != -1)
	let l:isFound = 0
	let l:isWrap = 0
	if &wrapscan
		let l:isFound = search(a:pattern, 'W' . a:flags)
		if ! l:isFound
			let l:isWrap = 1
		endif
	endif
	if ! l:isFound
		let l:isFound = search(a:pattern, a:flags) 
	endif
	if ! l:isFound
		call s:ErrorMessage(a:searchType, a:pattern)
	elseif l:isWrap
		call s:WrapMessage(a:searchType, a:pattern, l:isBackward)
	else
		call s:EchoSearchPattern(a:searchType, a:pattern, l:isBackward)
	endif
	return l:isFound
endfunction

" Combine all marks into one regexp. 
function! s:AnyMark()
	let w = ""
	let i = 0
	while i < g:mwCycleMax
		if !empty(g:mwWord[i])
			if w != ""
				let w = w . '\|' . g:mwWord[i]
			else
				let w = g:mwWord[i]
			endif
		endif
		let i += 1
	endwhile
	return w
endfunction

" Search any mark. 
function! mark#SearchAnyMark(...) " SearchAnyMark(flags)
	let flags = ""
	if a:0 > 0
		let flags = a:1
	endif
	let w = mark#CurrentMark()
	if w != ""
		let p = s:current_mark_position
	else
		let p = ""
	endif
	let w = s:AnyMark()
	let l:isFound =  s:Search(w, flags, 'any-mark')
	call mark#CurrentMark()
	if p == s:current_mark_position
		let l:isFound =  search(w, flags)
	endif
	let g:mwLastSearched = ""
	if l:isFound
		normal! zv
	endif
endfunction

" Search last searched mark. 
function! mark#SearchNext(...) " SearchNext(flags)
	let flags = ""
	if a:0 > 0
		let flags = a:1
	endif
	let w = mark#CurrentMark()
	if w != ""
		if g:mwLastSearched != ""
			call mark#SearchCurrentMark(flags)
		else
			call mark#SearchAnyMark(flags)
		endif
		return 1
	else
		return 0
	endif
endfunction

"- initializations ------------------------------------------------------------
augroup Mark
	autocmd!
	autocmd VimEnter * if ! exists('w:mwMatch') | call mark#UpdateMark() | endif
	autocmd WinEnter * if ! exists('w:mwMatch') | call mark#UpdateMark() | endif
	autocmd TabEnter * call mark#UpdateScope()
augroup END

" Define global variables and initialize current scope.  
function! s:InitMarkVariables()
	if !exists("g:mwHistAdd")
		let g:mwHistAdd = "/@"
	endif
	if !exists("g:mwCycleMax")
		let i = 1
		while hlexists("MarkWord" . i)
			let i = i + 1
		endwhile
		let g:mwCycleMax = i - 1
	endif
	if !exists("g:mwCycle")
		let g:mwCycle = 0
	endif
	if !exists("g:mwWord")
		let g:mwWord = repeat([''], g:mwCycleMax)
	endif
	if !exists("g:mwLastSearched")
		let g:mwLastSearched = ""
	endif
endfunction
call s:InitMarkVariables()
call mark#UpdateScope()

" vim: ts=2 sw=2
