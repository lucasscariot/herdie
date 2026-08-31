use herdie_core::{AnsiColor, TerminalModel};

#[test]
fn parses_text_cursor_and_ansi_styles() {
    let mut terminal = TerminalModel::new(12, 3, 100);
    terminal.process(b"hello\r\n\x1b[1;32mgreen\x1b[0m");

    let snapshot = terminal.snapshot();

    assert_eq!(snapshot.columns, 12);
    assert_eq!(snapshot.rows, 3);
    assert_eq!(snapshot.cursor.row, 1);
    assert_eq!(snapshot.cursor.column, 5);
    assert_eq!(snapshot.cell(0, 0).expect("h").contents, "h");
    let green = snapshot.cell(1, 0).expect("green g");
    assert_eq!(green.contents, "g");
    assert!(green.bold);
    assert_eq!(green.foreground, AnsiColor::Indexed { index: 2 });
}

#[test]
fn resize_changes_the_grid_without_resetting_visible_content() {
    let mut terminal = TerminalModel::new(8, 2, 100);
    terminal.process(b"herdie");

    terminal.resize(16, 4);
    let snapshot = terminal.snapshot();

    assert_eq!(snapshot.columns, 16);
    assert_eq!(snapshot.rows, 4);
    assert!(snapshot.plain_text().contains("herdie"));
}

#[test]
fn snapshots_are_json_round_trippable_for_mobile_bindings() {
    let mut terminal = TerminalModel::new(8, 2, 100);
    terminal.process(b"Herdie");

    let json = terminal.snapshot_json().expect("snapshot json");
    let decoded: serde_json::Value = serde_json::from_str(&json).expect("valid json");

    assert_eq!(decoded["columns"], 8);
    assert_eq!(decoded["rows"], 2);
    assert_eq!(decoded["cells"][0]["contents"], "H");
    assert_eq!(decoded["cells"][0]["foreground"]["kind"], "default");
}

#[test]
fn terminal_updates_send_a_full_frame_once_then_only_changed_cells() {
    let mut terminal = TerminalModel::new(8, 2, 100);
    terminal.process(b"abc");

    let first = terminal.take_update().expect("initial update");
    assert!(first.full);
    assert_eq!(first.cells.len(), 16);

    terminal.process(b"d");

    let second = terminal.take_update().expect("incremental update");
    assert!(!second.full);
    assert_eq!(second.cells.len(), 1);
    assert_eq!(second.cells[0].column, 3);
    assert_eq!(second.cells[0].contents, "d");
}

#[test]
fn terminal_update_is_omitted_when_visible_state_did_not_change() {
    let mut terminal = TerminalModel::new(8, 2, 100);
    terminal.process(b"abc");
    terminal.take_update().expect("initial update");

    assert!(terminal.take_update().is_none());
}

#[test]
fn mouse_wheel_input_targets_the_terminal_center_and_preserves_direction() {
    let terminal = TerminalModel::new(80, 24, 100);

    assert_eq!(
        terminal.mouse_wheel_input(2),
        b"\x1b[<64;41;13M\x1b[<64;41;13M"
    );
    assert_eq!(terminal.mouse_wheel_input(-1), b"\x1b[<65;41;13M");
    assert!(terminal.mouse_wheel_input(0).is_empty());
}

#[test]
fn scrollback_can_be_viewed_without_changing_terminal_contents() {
    let mut terminal = TerminalModel::new(8, 2, 100);
    terminal.process(b"first\r\nsecond\r\nthird");

    terminal.scroll(1);
    let older = terminal.snapshot();
    assert_eq!(older.scrollback_offset, 1);
    assert!(older.plain_text().contains("second"));

    terminal.scroll(0);
    let current = terminal.snapshot();
    assert_eq!(current.scrollback_offset, 0);
    assert!(current.plain_text().contains("third"));
}
