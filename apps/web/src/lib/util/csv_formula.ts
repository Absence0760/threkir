/**
 * Spreadsheet formula-injection guard for a cell of a CSV a person opens in
 * Excel, Sheets or Numbers. A cell that starts with `=`, `+`, `-` or `@` is
 * evaluated as a formula (`=HYPERLINK(...)`, `=WEBSERVICE(...)`), and quoting
 * the field does not stop it; a leading tab or CR is stripped by some of them
 * first, so it counts too. The value is prefixed with a single quote, which
 * every one of them reads as "this cell is text".
 *
 * Shared by every CSV writer whose cells carry text the downloader did not
 * type themselves (OWASP "CSV Injection").
 */
export function neutraliseSpreadsheetFormula(value: string): string {
	return /^[=+\-@\t\r]/.test(value) ? `'${value}` : value;
}
