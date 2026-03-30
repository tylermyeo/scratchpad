"""
Scratchpad - A minimal, beautiful plain-text editor for Mac
Ultra-simple note-taking with zero friction.
"""

import flet as ft


# Constants
WINDOW_WIDTH = 700
WINDOW_HEIGHT = 900
HEADER_HEIGHT = 50
PADDING_HORIZONTAL = 32
PADDING_VERTICAL = 24
TEXT_SIZE = 16
HEADER_TEXT_SIZE = 18
STATS_TEXT_SIZE = 12


def count_stats(text: str) -> tuple[int, int]:
    """
    Calculate word and character counts from text.
    
    Args:
        text: The text to analyze
        
    Returns:
        Tuple of (word_count, character_count)
    """
    if not text.strip():
        return (0, 0)
    
    words = len(text.split())
    chars = len(text)
    return (words, chars)


def format_stats(words: int, chars: int) -> str:
    """
    Format stats into a readable string.
    
    Args:
        words: Word count
        chars: Character count
        
    Returns:
        Formatted string like "245 words · 1,432 characters"
    """
    if words == 0 and chars == 0:
        return ""
    
    # Format numbers with commas
    words_str = f"{words:,}" if words > 0 else "0"
    chars_str = f"{chars:,}" if chars > 0 else "0"
    
    return f"{words_str} words · {chars_str} characters"


def main(page: ft.Page):
    """
    Main application entry point.
    Sets up the UI and event handlers.
    """
    # Window configuration
    page.title = "Scratchpad"
    page.window.width = WINDOW_WIDTH
    page.window.height = WINDOW_HEIGHT
    page.window.resizable = True
    page.window.min_width = 400
    page.window.min_height = 300
    
    # Theme configuration - follows system dark mode
    page.theme_mode = ft.ThemeMode.SYSTEM
    page.theme = ft.Theme(
        color_scheme_seed=ft.Colors.BLUE,
    )
    page.dark_theme = ft.Theme(
        color_scheme_seed=ft.Colors.BLUE_GREY,
    )
    
    # State
    text_field = ft.TextField(
        multiline=True,
        expand=True,
        border_color=ft.Colors.TRANSPARENT,
        text_size=TEXT_SIZE,
        hint_text="Start typing...",
        autofocus=True,
        min_lines=1,
    )
    
    stats_text = ft.Text(
        value="",
        size=STATS_TEXT_SIZE,
        color=ft.Colors.with_opacity(0.6, ft.Colors.ON_SURFACE),
        text_align=ft.TextAlign.RIGHT,
    )
    
    def update_stats(e=None):
        """Update the stats display when text changes."""
        text = text_field.value or ""
        words, chars = count_stats(text)
        stats_text.value = format_stats(words, chars)
        page.update()
    
    # Update stats when text changes
    text_field.on_change = update_stats
    
    def clear_text(e=None):
        """Show confirmation dialog and clear text if confirmed."""
        def on_confirm_clear(e):
            text_field.value = ""
            update_stats()
            page.close_dialog()
            text_field.focus()
            page.update()
        
        def on_cancel(e):
            page.close_dialog()
            text_field.focus()
            page.update()
        
        page.dialog = ft.AlertDialog(
            modal=True,
            title=ft.Text("Clear all text?"),
            content=ft.Text("This cannot be undone."),
            actions=[
                ft.TextButton("Cancel", on_click=on_cancel),
                ft.TextButton("Clear", on_click=on_confirm_clear),
            ],
            actions_alignment=ft.MainAxisAlignment.END,
        )
        page.dialog.open = True
        page.update()
    
    def on_keyboard(e: ft.KeyboardEvent):
        """Handle keyboard shortcuts."""
        # Cmd+K (or Ctrl+K on non-Mac) to clear
        if (e.key == "K" or e.key == "k") and (e.meta or e.ctrl):
            clear_text()
    
    # Set up keyboard event handler
    page.on_keyboard_event = on_keyboard
    
    # Header with title and stats
    header = ft.Container(
        content=ft.Row(
            controls=[
                ft.Text(
                    "Scratchpad",
                    size=HEADER_TEXT_SIZE,
                    weight=ft.FontWeight.W_600,
                ),
                stats_text,
            ],
            alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
        ),
        height=HEADER_HEIGHT,
        padding=ft.padding.only(
            left=PADDING_HORIZONTAL,
            right=PADDING_HORIZONTAL,
            top=PADDING_VERTICAL,
            bottom=8,
        ),
        border=ft.border.only(
            bottom=ft.BorderSide(1, ft.Colors.with_opacity(0.1, ft.Colors.ON_SURFACE))
        ),
    )
    
    # Main content area
    content = ft.Container(
        content=text_field,
        padding=ft.padding.symmetric(
            horizontal=PADDING_HORIZONTAL,
            vertical=PADDING_VERTICAL,
        ),
        expand=True,
    )
    
    # Main layout
    page.add(
        ft.Column(
            controls=[header, content],
            spacing=0,
            expand=True,
        )
    )
    
    # Initial focus on text field
    text_field.focus()


if __name__ == "__main__":
    ft.run(main)
