function Stop-TerraformGraphCommand {
    # Not exported. The one way this module raises a terminating error (DECISIONS 50): every
    # id is a literal here at the call site, so the Pester error-id test can list them all.
    # Deliberately not an advanced function: $PSCmdlet resolves to the calling command's, so
    # the FullyQualifiedErrorId reads '<Id>,<exported command>' as it always has.
    # $PSCmdlet.ThrowTerminatingError cannot be caught by the caller's own try/catch, so a
    # private helper whose caller catches and rewraps the error passes -Throw, which throws
    # the same ErrorRecord as an ordinary (catchable) exception.
    param(
        [string]$Id,
        [string]$Message,
        [System.Management.Automation.ErrorCategory]$Category = 'InvalidOperation',
        $Target,
        [type]$ExceptionType = [System.InvalidOperationException],
        [System.Exception]$InnerException,
        [switch]$Throw
    )
    $exception = if ($InnerException) { $ExceptionType::new($Message, $InnerException) } else { $ExceptionType::new($Message) }
    $record = [System.Management.Automation.ErrorRecord]::new($exception, $Id, $Category, $Target)
    if ($Throw -or -not $PSCmdlet) { throw $record }
    $PSCmdlet.ThrowTerminatingError($record)
}
