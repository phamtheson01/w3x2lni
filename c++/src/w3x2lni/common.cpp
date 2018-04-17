#include "common.h"
#include <shlwapi.h>
#include <algorithm>
#include <utility>
#pragma comment(lib, "shlwapi.lib")

strview::strview(const wchar_t* str)
	: buf(str)
	, len(wcslen(str))
{ }

path::path() {
	::GetModuleFileNameW(NULL, buf, sizeof buf / sizeof buf[0]);
	::PathRemoveBlanksW(buf);
	::PathUnquoteSpacesW(buf);
	::PathRemoveBackslashW(buf);
	::PathRemoveFileSpecW(buf);
#if _DEBUG
	::PathRemoveFileSpecW(buf);
	::PathRemoveFileSpecW(buf);
	::PathRemoveFileSpecW(buf);
	::PathRemoveFileSpecW(buf);
	::PathRemoveFileSpecW(buf);
#endif
	len = wcslen(buf);
}



pipe::~pipe() {
	if (f) CloseHandle(f);
	if (h) CloseHandle(h);
}
bool pipe::open(int type) {
	SECURITY_ATTRIBUTES sa;
	sa.nLength = sizeof(SECURITY_ATTRIBUTES);
	sa.bInheritHandle = FALSE;
	sa.lpSecurityDescriptor = NULL;
	HANDLE rd = NULL, wr = NULL;
	if (!::CreatePipe(&rd, &wr, &sa, 0)) {
		return false;
	}
	f = type == 'r' ? rd : wr;
	h = type == 'r' ? wr : rd;
	::SetHandleInformation(h, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
	return true;
}

size_t pipe::read(char* buf, size_t len) {
	DWORD rlen = 0;
	if (!PeekNamedPipe(f, 0, 0, 0, &rlen, 0)) {
		return -1;
	}
	if (rlen == 0) {
		return 0;
	}
	if (!ReadFile(f, buf, (std::min)(rlen, (DWORD)len), &rlen, 0)) {
		return -1;
	}
	return (size_t)rlen;
}

bool execute_lua(const wchar_t* who, pipe* out, pipe* err) {
	path app = path() / L"bin" / L"w3x2lni-lua.exe";
	path cwd = path() / L"script";
	strbuilder<32768> cmd;
	cmd += L"\"";
	cmd += app;
	cmd += L"\" -e \"_W3X2LNI='";
	cmd += who;
	cmd += L"'\" -E \"";
	cmd += path() / L"script" / L"main.lua";
	cmd += L"\"";

	for (int i = 1; i < __argc; ++i) {
		cmd += L" \"";
		cmd += __wargv[i];
		cmd += L"\"";
	}

	strbuilder<1024> env;
	env += L"PATH=";
	env += path() / L"bin";
	env += L"\0";

	PROCESS_INFORMATION     pi = { 0 };
	STARTUPINFOW            si = { sizeof STARTUPINFOW };
	si.dwFlags = STARTF_USESTDHANDLES;
	si.hStdInput = INVALID_HANDLE_VALUE;
	si.hStdOutput = INVALID_HANDLE_VALUE;
	si.hStdError = INVALID_HANDLE_VALUE;
	if (out) {
		si.hStdOutput = out->h;
		out->h = NULL;
	}
	if (err) {
		si.hStdError = err->h;
		err->h = NULL;
	}

	if (!::CreateProcessW(
		app.string(),
		cmd.string(),
		NULL, NULL, TRUE,
		NORMAL_PRIORITY_CLASS | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
		env.string(),
		cwd.string(),
		&si, &pi))
	{
		return false;
	}

	::CloseHandle(si.hStdInput);
	::CloseHandle(si.hStdOutput);
	::CloseHandle(si.hStdError);
	::CloseHandle(pi.hThread);
	::CloseHandle(pi.hProcess);

	return true;
}