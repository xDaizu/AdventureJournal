#!/usr/bin/env python3
"""Exporta el SavedVariables AdventureJournalDB de WoW a un TXT legible."""
import os
import re
import tkinter as tk
from tkinter import filedialog, messagebox

TOKEN_RE = re.compile(
    r'\s+|--[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|'
    r'\[\]|[{}\[\]=,;]|-?\d+(?:\.\d+)?|[A-Za-z_][A-Za-z0-9_]*'
)

class LuaParser:
    def __init__(self, source):
        self.tokens = [t for t in TOKEN_RE.findall(source) if not t.isspace() and not t.startswith('--')]
        self.i = 0

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else None

    def pop(self):
        token = self.peek()
        if token is None:
            raise ValueError('Fin inesperado del archivo Lua.')
        self.i += 1
        return token

    def parse_string(self, token):
        raw = token[1:-1]
        out, i = [], 0
        mapping = {'n':'\n', 'r':'\r', 't':'\t', 'b':'\b', 'f':'\f', '\\':'\\', '"':'"', "'":"'"}
        while i < len(raw):
            if raw[i] != '\\':
                out.append(raw[i]); i += 1; continue
            i += 1
            if i >= len(raw): break
            char = raw[i]
            if char in mapping:
                out.append(mapping[char]); i += 1
            elif char.isdigit():
                match = re.match(r'\d{1,3}', raw[i:])
                out.append(chr(int(match.group(0)))); i += len(match.group(0))
            elif char == '\n':
                out.append('\n'); i += 1
            else:
                out.append(char); i += 1
        return ''.join(out)

    def value(self):
        token = self.peek()
        if token == '{': return self.table()
        token = self.pop()
        if token.startswith(('"', "'")): return self.parse_string(token)
        if token == 'true': return True
        if token == 'false': return False
        if token == 'nil': return None
        try:
            return float(token) if '.' in token else int(token)
        except ValueError:
            return token

    def table(self):
        self.pop()
        result, array_index = {}, 1
        while self.peek() and self.peek() != '}':
            if self.peek() in (',', ';'):
                self.pop(); continue
            if self.peek() == '[':
                self.pop(); key = self.value()
                if self.pop() != ']': raise ValueError('Clave Lua mal formada.')
                if self.pop() != '=': raise ValueError('Falta = después de una clave.')
                result[key] = self.value()
            elif (self.i + 1 < len(self.tokens)
                  and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', self.tokens[self.i])
                  and self.tokens[self.i + 1] == '='):
                key = self.pop(); self.pop(); result[key] = self.value()
            else:
                result[array_index] = self.value(); array_index += 1
            if self.peek() in (',', ';'): self.pop()
        if self.pop() != '}': raise ValueError('Tabla Lua sin cerrar.')
        return result


def find_database(source):
    match = re.search(r'\bAdventureJournalDB\s*=\s*\{', source)
    if not match:
        raise ValueError('No encuentro AdventureJournalDB en el archivo seleccionado.')
    parser = LuaParser(source[match.start():])
    parser.pop(); parser.pop()
    return parser.value()


def clean(value):
    if value is None: return ''
    text = str(value)
    text = re.sub(r'\|c[0-9A-Fa-f]{8}|\|r', '', text)
    text = re.sub(r'\|Hitem:[^|]*\|h\[([^]]+)\]\|h', r'\1', text)
    return text


def ordered_values(table):
    def key_order(key):
        try: return (0, int(key))
        except (TypeError, ValueError): return (1, str(key))
    return [table[key] for key in sorted(table, key=key_order)]


def export_text(db):
    days = db.get('days', {}) or {}
    max_day = int(db.get('currentDay', 0) or 0)
    lines = ['DIARIO DE AVENTURAS', '=' * 64, '']
    for day_number in range(1, max_day + 1):
        day = days.get(day_number, days.get(str(day_number), {})) or {}
        events = day.get('events', {}) or {}
        lines.extend([
            f"JORNADA {day_number} — {clean(day.get('dateLabel', 'Fecha desconocida'))}",
            f"Inicio de sesión: {clean(day.get('startedAt', ''))}",
            f"Fin de sesión: {clean(day.get('endedAt', ''))}",
            '-' * 64,
        ])
        event_values = ordered_values(events) if isinstance(events, dict) else []
        if not event_values:
            lines.append('No quedaron acontecimientos registrados durante esta jornada.')
        else:
            for entry in event_values:
                lines.append(f"[{clean(entry.get('time', ''))}] {clean(entry.get('prose') or entry.get('text', ''))}")
                lines.append('')
        lines.append('')
    return '\n'.join(lines).rstrip() + '\n'


def main():
    root = tk.Tk(); root.withdraw()
    path = filedialog.askopenfilename(
        title='Selecciona AdventureJournal.lua de SavedVariables',
        filetypes=[('Variables guardadas de WoW', 'AdventureJournal.lua'), ('Archivos Lua', '*.lua'), ('Todos', '*.*')]
    )
    if not path: return
    try:
        with open(path, 'r', encoding='utf-8-sig') as source_file:
            db = find_database(source_file.read())
        output_text = export_text(db)
        character_folder = os.path.basename(os.path.dirname(os.path.dirname(path)))
        output_path = os.path.join(os.path.dirname(path), f'Diario_{character_folder}.txt')
        with open(output_path, 'w', encoding='utf-8') as output_file:
            output_file.write(output_text)
        messagebox.showinfo('Diario exportado', f'Archivo creado correctamente:\n\n{output_path}')
    except Exception as error:
        messagebox.showerror('No se pudo exportar', str(error))

if __name__ == '__main__':
    main()
