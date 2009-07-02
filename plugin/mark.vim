" Script Name: mark.vim
" Version:     2.1.0 (global version)
" Last Change: June 6, 2009
"
" Copyright:   (C) 2005-2008 by Yuheng Xie
"              (C) 2008-2009 by Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'. 
"
" Maintainer:  Ingo Karkat <ingo@karkat.de> 
" Orig Author: Yuheng Xie <elephant@linux.net.cn>
" Contributors:Luc Hermitte, Ingo Karkat
"
" Dependencies:
"  - Vim 7.1 with "matchadd()", or Vim 7.2 or higher. 
"  - SearchSpecial.vim autoload script (optional, for improved search messages). 
"
" Description: Highlight several words in different colors simultaneously. 
"
" Usage:       :Mark regexp   to mark a regular expression
"              :Mark regexp   with exactly the same regexp to unmark it
"              :Mark          to clear all marks
"
"              You may map keys for the call in your vimrc file for
"              convenience. The default keys is:
"              Highlighting:
"                Normal \m  mark or unmark the word under or before the cursor
"                       \r  manually input a regular expression
"                       \n  clear current mark (i.e. the mark under the cursor),
"                           or clear all marks
"                Visual \m  mark or unmark a visual selection
"                       \r  manually input a regular expression
"              Searching:
"                Normal \*  jump to the next occurrence of current mark
"                       \#  jump to the previous occurrence of current mark
"                       \/  jump to the next occurrence of ANY mark
"                       \?  jump to the previous occurrence of ANY mark
"                        *  behaviors vary, please refer to the table on
"                        #  line 123
"                combined with Vim's / and ? etc.
"
"              The default colors/groups setting is for marking six
"              different words in different colors. You may define your own
"              colors in your vimrc file. That is to define highlight group
"              names as "MarkWordN", where N is a number. An example could be
"              found below.
"
" Bugs:
"
" TODO:
" 
" Changes:
" 6th Jun 2009, Ingo Karkat
"  1. Somehow s:WrapMessage() needs a redraw before the :echo to avoid that a
"     later Vim redraw clears the wrap message. This happened when there's no
"     statusline and thus :echo'ing into the ruler. 
"  2. Removed line-continuations and ':set cpo=...'. Upper-cased <SID> and <CR>. 
"  3. Added default highlighting for the special search type. 
"
" 2nd Jun 2009, Ingo Karkat
"  1. Replaced highlighting via :syntax with matchadd() / matchdelete(). This
"     requires Vim 7.2 / 7.1 with patches. This method is faster, there are no
"     more clashes with syntax highlighting (:match always has preference), and
"     the background highlighting does not disappear under 'cursorline'. 
"  2. Factored :windo application out into s:MarkScope(). 
"  3. Using winrestcmd() to fix effects of :windo: By entering a window, its
"     height is potentially increased from 0 to 1. 
"  4. Handling multiple tabs by calling s:UpdateScope() on the TabEnter event. 
"     
" 1st Jun 2009, Ingo Karkat
"  1. Now using Vim List for g:mwWord and thus requiring Vim 7. g:mwCycle is now
"     zero-based, but the syntax groups "MarkWordx" are still one-based. 
"  2. Added missing setter for re-inclusion guard. 
"  3. Factored :syntax operations out of s:DoMark() and s:UpdateMark() so that
"     they can all be done in a single :windo. 
"  4. Normal mode <Plug>MarkSet now has the same semantics as its visual mode
"     cousin: If the cursor is on an existing mark, the mark is removed.
"     Beforehand, one could only remove a visually selected mark via again
"     selecting it. Now, one simply can invoke the mapping when on such a mark. 
"  5. Highlighting can now actually be overridden in the vimrc (anywhere
"     _before_ sourcing this script) by using ':hi def'. 
"
" 31st May 2009, Ingo Karkat
"  1. Refactored s:Search() to optionally take advantage of SearchSpecial.vim
"     autoload functionality for echoing of search pattern, wrap and error
"     messages. 
"  2. Now prepending search type ("any-mark", "same-mark", "new-mark") for
"     better identification. 
"  3. Retired the algorithm in s:PrevWord in favor of simply using <cword>,
"     which makes mark.vim work like the * command. At the end of a line,
"     non-keyword characters may now be marked; the previous algorithm prefered
"     any preceding word. 
"  4. BF: If 'iskeyword' contains characters that have a special meaning in a
"     regex (e.g. [.*]), these are now escaped properly. 
"
" 1st Sep 2008, Ingo Karkat: bugfixes and enhancements
"  1. Added <Plug>MarkAllClear (without a default mapping), which clears all
"     marks, even when the cursor is on a mark.
"  2. Added <Plug>... mappings for hard-coded \*, \#, \/, \?, * and #, to allow
"     re-mapping and disabling. Beforehand, there were some <Plug>... mappings
"     and hard-coded ones; now, everything can be customized.
"  3. Bugfix: Using :autocmd without <bang> to avoid removing _all_ autocmds for
"     the BufWinEnter event. (Using a custom :augroup would be even better.)
"  4. Bugfix: Explicitly defining s:current_mark_position; some execution paths
"     left it undefined, causing errors.
"  5. Refactoring: Instead of calling s:InitMarkVariables() at the beginning of
"     several functions, just calling it once when sourcing the script.
"  6. Refactoring: Moved multiple 'let lastwinnr = winnr()' to a single one at the
"     top of DoMark().
"  7. ENH: Make the match according to the 'ignorecase' setting, like the star
"     command.
"  8. The jumps to the next/prev occurrence now print 'search hit BOTTOM,
"     continuing at TOP" and "Pattern not found:..." messages, like the * and
"     n/N Vim search commands.
"  9. Jumps now open folds if the occurrence is inside a closed fold, just like n/N
"     do. 
"
" 10th Mar 2006, Yuheng Xie: jump to ANY mark
" (*) added \* \# \/ \? for the ability of jumping to ANY mark, even when the
"     cursor is not currently over any mark
"
" 20th Sep 2005, Yuheng Xie: minor modifications
" (*) merged MarkRegexVisual into MarkRegex
" (*) added GetVisualSelectionEscaped for multi-lines visual selection and
"     visual selection contains ^, $, etc.
" (*) changed the name ThisMark to CurrentMark
" (*) added SearchCurrentMark and re-used raw map (instead of Vim function) to
"     implement * and #
"
" 14th Sep 2005, Luc Hermitte: modifications done on v1.1.4
" (*) anti-reinclusion guards. They do not guard colors definitions in case
"     this script must be reloaded after .gvimrc
" (*) Protection against disabled |line-continuation|s.
" (*) Script-local functions
" (*) Default keybindings
" (*) \r for visual mode
" (*) uses <leader> instead of "\"
" (*) do not mess with global variable g:w
" (*) regex simplified -> double quotes changed into simple quotes.
" (*) strpart(str, idx, 1) -> str[idx]
" (*) command :Mark
"     -> e.g. :Mark Mark.\{-}\ze(

" Anti reinclusion guards
if (exists('g:loaded_mark') && !exists('g:force_reload_mark')) || (v:version == 701 && ! exists('*matchadd')) || (v:version < 702)
	finish
endif
let g:loaded_mark = 1

" default colors/groups
" you may define your own colors in your vimrc file, in the form as below:
highlight def MarkWord1  ctermbg=Cyan     ctermfg=Black  guibg=#8CCBEA    guifg=Black
highlight def MarkWord2  ctermbg=Green    ctermfg=Black  guibg=#A4E57E    guifg=Black
highlight def MarkWord3  ctermbg=Yellow   ctermfg=Black  guibg=#FFDB72    guifg=Black
highlight def MarkWord4  ctermbg=Red      ctermfg=Black  guibg=#FF7272    guifg=Black
highlight def MarkWord5  ctermbg=Magenta  ctermfg=Black  guibg=#FFB3FF    guifg=Black
highlight def MarkWord6  ctermbg=Blue     ctermfg=Black  guibg=#9999FF    guifg=Black

" Default highlighting for the special search type. 
" You can override this by defining / linking the 'SearchSpecialSearchType'
" highlight group before this script is sourced. 
highlight def link SearchSpecialSearchType MoreMsg


" Default bindings

if !hasmapto('<Plug>MarkSet', 'n')
	nmap <unique> <silent> <leader>m <Plug>MarkSet
endif
if !hasmapto('<Plug>MarkSet', 'v')
	vmap <unique> <silent> <leader>m <Plug>MarkSet
endif
if !hasmapto('<Plug>MarkRegex', 'n')
	nmap <unique> <silent> <leader>r <Plug>MarkRegex
endif
if !hasmapto('<Plug>MarkRegex', 'v')
	vmap <unique> <silent> <leader>r <Plug>MarkRegex
endif
if !hasmapto('<Plug>MarkClear', 'n')
	nmap <unique> <silent> <leader>n <Plug>MarkClear
endif

nnoremap <silent> <Plug>MarkSet   :call <SID>MarkCurrentWord()<CR>
vnoremap <silent> <Plug>MarkSet   <c-\><c-n>:call <SID>DoMark(<SID>GetVisualSelectionEscaped("enV"))<CR>
nnoremap <silent> <Plug>MarkRegex :call <SID>MarkRegex()<CR>
vnoremap <silent> <Plug>MarkRegex <c-\><c-n>:call <SID>MarkRegex(<SID>GetVisualSelectionEscaped("N"))<CR>
nnoremap <silent> <Plug>MarkClear :call <SID>DoMark(<SID>CurrentMark())<CR>
nnoremap <silent> <Plug>MarkAllClear :call <SID>DoMark()<CR>

" Here is a sumerization of the following keys' behaviors:
" 
" First of all, \#, \? and # behave just like \*, \/ and *, respectively,
" except that \#, \? and # search backward.
"
" \*, \/ and *'s behaviors differ base on whether the cursor is currently
" placed over an active mark:
"
"       Cursor over mark                  Cursor not over mark
" ---------------------------------------------------------------------------
"  \*   jump to the next occurrence of    jump to the next occurrence of
"       current mark, and remember it     "last mark".
"       as "last mark".
"
"  \/   jump to the next occurrence of    same as left
"       ANY mark.
"
"   *   if \* is the most recently used,  do Vim's original *
"       do a \*; otherwise (\/ is the
"       most recently used), do a \/.

nnoremap <silent> <Plug>MarkSearchCurrentNext :call <SID>SearchCurrentMark()<CR>
nnoremap <silent> <Plug>MarkSearchCurrentPrev :call <SID>SearchCurrentMark("b")<CR>
nnoremap <silent> <Plug>MarkSearchAnyNext     :call <SID>SearchAnyMark()<CR>
nnoremap <silent> <Plug>MarkSearchAnyPrev     :call <SID>SearchAnyMark("b")<CR>
nnoremap <silent> <Plug>MarkSearchNext        :if !<SID>SearchNext()<bar>execute "norm! *zv"<bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchPrev        :if !<SID>SearchNext("b")<bar>execute "norm! #zv"<bar>endif<CR>
" When typed, [*#nN] open the fold at the search result, but inside a mapping or
" :normal this must be done explicitly via 'zv'. 


if !hasmapto('<Plug>MarkSearchCurrentNext', 'n')
	nmap <unique> <silent> <leader>* <Plug>MarkSearchCurrentNext
endif
if !hasmapto('<Plug>MarkSearchCurrentPrev', 'n')
	nmap <unique> <silent> <leader># <Plug>MarkSearchCurrentPrev
endif
if !hasmapto('<Plug>MarkSearchAnyNext', 'n')
	nmap <unique> <silent> <leader>/ <Plug>MarkSearchAnyNext
endif
if !hasmapto('<Plug>MarkSearchAnyPrev', 'n')
	nmap <unique> <silent> <leader>? <Plug>MarkSearchAnyPrev
endif
if !hasmapto('<Plug>MarkSearchNext', 'n')
	nmap <unique> <silent> * <Plug>MarkSearchNext
endif
if !hasmapto('<Plug>MarkSearchPrev', 'n')
	nmap <unique> <silent> # <Plug>MarkSearchPrev
endif

command! -nargs=? Mark call <SID>DoMark(<f-args>)

augroup Mark
	autocmd!
	autocmd VimEnter * if ! exists('w:mwMatch') | call <SID>UpdateMark() | endif
	autocmd WinEnter * if ! exists('w:mwMatch') | call <SID>UpdateMark() | endif
	autocmd TabEnter * call <SID>UpdateScope()
augroup END

" Script variables
let s:current_mark_position = ''

" Functions

function! s:EscapeText( text )
	return substitute( escape(a:text, '\' . '^$.*[~'), "\n", '\\n', 'ge' )
endfunction
" Mark the current word, like the built-in star command. 
" If the cursor is on an existing mark, remove it. 
function! s:MarkCurrentWord()
	let l:regexp = s:CurrentMark()
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
		call s:DoMark(l:regexp)
	endif
endfunction

function! s:GetVisualSelection()
	let save_a = @a
	silent normal! gv"ay
	let res = @a
	let @a = save_a
	return res
endfunction

function! s:GetVisualSelectionEscaped(flags)
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

" manually input a regular expression
function! s:MarkRegex(...) " MarkRegex(regexp)
	let regexp = ""
	if a:0 > 0
		let regexp = a:1
	endif
	call inputsave()
	let r = input("@", regexp)
	call inputrestore()
	if r != ""
		call s:DoMark(r)
	endif
endfunction

" define variables if they don't exist
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
function! s:UpdateScope()
	let l:currentWinNr = winnr()

	" By entering a window, its height is potentially increased from 0 to 1 (the
	" minimum for the current window). To avoid any modification, save the window
	" sizes and restore them after visiting all windows. 
	let l:originalWindowLayout = winrestcmd() 

	noautocmd windo call s:UpdateMark()
	execute l:currentWinNr . 'wincmd w'
	silent! execute l:originalWindowLayout
endfunction
" mark or unmark a regular expression
function! s:DoMark(...) " DoMark(regexp)
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
" initialize mark colors in a (new) window
function! s:UpdateMark()
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

" return the mark string under the cursor. multi-lines marks not supported
function! s:CurrentMark()
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

" search current mark
function! s:SearchCurrentMark(...) " SearchCurrentMark(flags)
	let flags = ""
	let l:isFound = 0
	if a:0 > 0
		let flags = a:1
	endif
	let w = s:CurrentMark()
	if w != ""
		let p = s:current_mark_position
		let l:isFound = s:Search(w, flags, (w ==# g:mwLastSearched ? 'same-mark' : 'new-mark'))
		call s:CurrentMark()
		if p == s:current_mark_position
			let l:isFound = search(w, flags)
		endif
		let g:mwLastSearched = w
	else
		if g:mwLastSearched != ""
			let l:isFound = s:Search(g:mwLastSearched, flags, 'same-mark')
		else
			call s:SearchAnyMark(flags)
			let g:mwLastSearched = s:CurrentMark()
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

" wrapper around search() with additonal search and error messages and "wrapscan" warning
function! s:Search( pattern, flags, searchType)
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

" combine all marks into one regexp
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

" search any mark
function! s:SearchAnyMark(...) " SearchAnyMark(flags)
	let flags = ""
	if a:0 > 0
		let flags = a:1
	endif
	let w = s:CurrentMark()
	if w != ""
		let p = s:current_mark_position
	else
		let p = ""
	endif
	let w = s:AnyMark()
	let l:isFound =  s:Search(w, flags, 'any-mark')
	call s:CurrentMark()
	if p == s:current_mark_position
		let l:isFound =  search(w, flags)
	endif
	let g:mwLastSearched = ""
	if l:isFound
		normal! zv
	endif
endfunction

" search last searched mark
function! s:SearchNext(...) " SearchNext(flags)
	let flags = ""
	if a:0 > 0
		let flags = a:1
	endif
	let w = s:CurrentMark()
	if w != ""
		if g:mwLastSearched != ""
			call s:SearchCurrentMark(flags)
		else
			call s:SearchAnyMark(flags)
		endif
		return 1
	else
		return 0
	endif
endfunction


" Define global variables once
call s:InitMarkVariables()

" vim: ts=2 sw=2
