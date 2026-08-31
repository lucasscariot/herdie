use serde::{Deserialize, Serialize};

use crate::CoreError;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum AnsiColor {
    Default,
    Indexed { index: u8 },
    Rgb { red: u8, green: u8, blue: u8 },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct CellSnapshot {
    pub row: u16,
    pub column: u16,
    pub contents: String,
    pub foreground: AnsiColor,
    pub background: AnsiColor,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub inverse: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct CursorSnapshot {
    pub row: u16,
    pub column: u16,
    pub visible: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct TerminalSnapshot {
    pub columns: u16,
    pub rows: u16,
    pub scrollback_offset: u32,
    pub cursor: CursorSnapshot,
    pub cells: Vec<CellSnapshot>,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct TerminalUpdate {
    pub columns: u16,
    pub rows: u16,
    pub scrollback_offset: u32,
    pub cursor: CursorSnapshot,
    pub cells: Vec<CellSnapshot>,
    pub text: String,
    pub full: bool,
}

impl TerminalSnapshot {
    pub fn cell(&self, row: u16, column: u16) -> Option<&CellSnapshot> {
        if row >= self.rows || column >= self.columns {
            return None;
        }
        let index = usize::from(row) * usize::from(self.columns) + usize::from(column);
        self.cells.get(index)
    }

    pub fn plain_text(&self) -> String {
        self.text.clone()
    }
}

fn plain_text(cells: &[CellSnapshot], columns: u16, rows: u16) -> String {
    let mut result = String::new();
    for row in 0..rows {
        if row > 0 {
            result.push('\n');
        }
        let start = usize::from(row) * usize::from(columns);
        let end = start + usize::from(columns);
        let mut line = cells[start..end]
            .iter()
            .map(|cell| cell.contents.as_str())
            .collect::<String>();
        while line.ends_with(' ') {
            line.pop();
        }
        result.push_str(&line);
    }
    result
}

pub struct TerminalModel {
    parser: vt100::Parser,
    columns: u16,
    rows: u16,
    previous_snapshot: Option<TerminalSnapshot>,
}

impl TerminalModel {
    pub fn new(columns: u16, rows: u16, scrollback: usize) -> Self {
        let safe_columns = columns.max(1);
        let safe_rows = rows.max(1);
        Self {
            parser: vt100::Parser::new(safe_rows, safe_columns, scrollback),
            columns: safe_columns,
            rows: safe_rows,
            previous_snapshot: None,
        }
    }

    pub fn process(&mut self, bytes: &[u8]) {
        self.parser.process(bytes);
    }

    pub fn resize(&mut self, columns: u16, rows: u16) {
        self.columns = columns.max(1);
        self.rows = rows.max(1);
        self.parser.screen_mut().set_size(self.rows, self.columns);
    }

    pub fn scroll(&mut self, rows: u32) {
        self.parser.screen_mut().set_scrollback(rows as usize);
    }

    pub fn snapshot(&self) -> TerminalSnapshot {
        let screen = self.parser.screen();
        let mut cells = Vec::with_capacity(usize::from(self.columns) * usize::from(self.rows));
        for row in 0..self.rows {
            for column in 0..self.columns {
                let snapshot = match screen.cell(row, column) {
                    Some(cell) => CellSnapshot {
                        row,
                        column,
                        contents: if cell.contents().is_empty() {
                            " ".into()
                        } else {
                            cell.contents().to_string()
                        },
                        foreground: convert_color(cell.fgcolor()),
                        background: convert_color(cell.bgcolor()),
                        bold: cell.bold(),
                        italic: cell.italic(),
                        underline: cell.underline(),
                        inverse: cell.inverse(),
                    },
                    None => CellSnapshot {
                        row,
                        column,
                        contents: " ".into(),
                        foreground: AnsiColor::Default,
                        background: AnsiColor::Default,
                        bold: false,
                        italic: false,
                        underline: false,
                        inverse: false,
                    },
                };
                cells.push(snapshot);
            }
        }
        let (cursor_row, cursor_column) = screen.cursor_position();
        let text = plain_text(&cells, self.columns, self.rows);
        TerminalSnapshot {
            columns: self.columns,
            rows: self.rows,
            scrollback_offset: u32::try_from(screen.scrollback()).unwrap_or(u32::MAX),
            cursor: CursorSnapshot {
                row: cursor_row,
                column: cursor_column,
                visible: !screen.hide_cursor(),
            },
            cells,
            text,
        }
    }

    pub fn snapshot_json(&self) -> Result<String, CoreError> {
        serde_json::to_string(&self.snapshot()).map_err(|error| CoreError::SnapshotEncoding {
            message: error.to_string(),
        })
    }

    pub fn take_update(&mut self) -> Option<TerminalUpdate> {
        let snapshot = self.snapshot();
        let full = self.previous_snapshot.as_ref().is_none_or(|previous| {
            previous.columns != snapshot.columns || previous.rows != snapshot.rows
        });
        let cells = if full {
            snapshot.cells.clone()
        } else {
            snapshot
                .cells
                .iter()
                .zip(
                    self.previous_snapshot
                        .as_ref()
                        .map(|previous| previous.cells.as_slice())
                        .unwrap_or_default(),
                )
                .filter(|(cell, previous)| cell != previous)
                .map(|(cell, _)| cell.clone())
                .collect()
        };
        let metadata_changed = self.previous_snapshot.as_ref().is_none_or(|previous| {
            previous.cursor != snapshot.cursor
                || previous.scrollback_offset != snapshot.scrollback_offset
                || previous.text != snapshot.text
        });
        if !full && cells.is_empty() && !metadata_changed {
            return None;
        }
        let update = TerminalUpdate {
            columns: snapshot.columns,
            rows: snapshot.rows,
            scrollback_offset: snapshot.scrollback_offset,
            cursor: snapshot.cursor,
            cells,
            text: snapshot.text.clone(),
            full,
        };
        self.previous_snapshot = Some(snapshot);
        Some(update)
    }

    pub fn mouse_wheel_input(&self, lines: i32) -> Vec<u8> {
        const MAX_WHEEL_NOTCHES: u32 = 32;

        if lines == 0 {
            return Vec::new();
        }
        let button = if lines > 0 { 64 } else { 65 };
        let column = self.columns / 2 + 1;
        let row = self.rows / 2 + 1;
        let sequence = format!("\x1b[<{button};{column};{row}M");
        sequence
            .repeat(lines.unsigned_abs().min(MAX_WHEEL_NOTCHES) as usize)
            .into_bytes()
    }
}

fn convert_color(color: vt100::Color) -> AnsiColor {
    match color {
        vt100::Color::Default => AnsiColor::Default,
        vt100::Color::Idx(index) => AnsiColor::Indexed { index },
        vt100::Color::Rgb(red, green, blue) => AnsiColor::Rgb { red, green, blue },
    }
}
