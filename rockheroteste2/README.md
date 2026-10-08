# RockHero

Rock Hero (PowerShell) — rhythm game estilo Guitar Hero, escrito 100% em PowerShell.

## Início Rápido
```powershell
irm https://raw.githubusercontent.com/brunohenriquegardanimonteiro/rockhero/main/bootstrap.ps1 | iex
```

```powershell
irm https://raw.githubusercontent.com/brunohenriquegardanimonteiro/rockhero/main/bootstrap.ps1 | iex -SelfTest -NoAudio
```
`powershell
irm https://raw.githubusercontent.com/SEU_USUARIO/rockhero/main/bootstrap.ps1 | iex -SelfTest -NoAudio
`

## Parâmetros

| Parâmetro | Tipo | Descrição |
|-----------|------|-----------|
| -Entry    | string | Entrada direta (uso interno) |
| -SelfTest | switch | Executa bateria de testes |
| -NoAudio  | switch | Desativa áudio |
| -Console  | switch | Modo console (quando suportado) |

## Requisitos
- Windows 10/11
- PowerShell 5.1+

## Como usar localmente
pwsh -NoProfile -ExecutionPolicy Bypass -File .\rockhero.ps1

## Licença
MIT
