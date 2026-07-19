class_name GoapActions
extends Node

const EAT := "Eat"
const REST := "Rest"
const PICKUP_FOOD := "PickupFood"
const PICKUP_WOOD := "PickupWood"
const DEPOSIT_RESOURCE := "DepositResource"
const RANDOM_EXPLORE := "RandomExplore"
const REPORT_RESOURCE := "ReportResource"
const REPORT_DEPLETION := "ReportDepletion"
const IDLE := "Idle"

## Base name for the grounded travel action (CONTEXT.md: GoTo). Never appears
## alone in a plan or a role config - the Planner grounds it into "GoTo[Kind]"
## instances (see GotoGrounding), and GoapActionExecutor dispatches on the
## "GoTo[" prefix rather than this exact name.
const GOTO := "GoTo"

## Base name for the grounded Nest-withdrawal action (SPEC.md
## .scratch/survival-loop Ticket 03). Mirrors GOTO's shape: grounded into
## "GetResource[Kind]" instances (see GetResourceGrounding), dispatched on
## the "GetResource[" prefix. Unlike GOTO, not a Universal Capability -
## Gatherer's role config lists the concrete grounded instance names
## directly.
const GET_RESOURCE := "GetResource"
