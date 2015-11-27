//
//	Admin Account Management -- Password reset
//
//	FLOW:
//		DoActionReset
//			TableAadAdd
//			ActionResetProcess
//			ActionResetCheck
//			ActionResetInformByEmail
//


unit aam_action_reset;


{$MODE OBJFPC}
{$H+}			// Large string support (Ansistring)


interface


uses
	SysUtils,
	Process,
	USupportLibrary,
	ODBCConn,
	SqlDb,
	aam_global;
	

procedure DoActionReset(curAction: integer);			// Add new actions to the table AAD for password resets


implementation



procedure TableArpSetStatus(recId: integer; newStatus: integer);
var
	qu: Ansistring;
begin
	qu := 'UPDATE ' + VIEW_RESET;
	qu := qu + ' SET';
	qu := qu + ' ' + VIEW_RESET_STATUS + '=' + IntToStr(newStatus);
	qu := qu + ' WHERE ' + VIEW_RESET_ID + '=' + IntToStr(recId);
	qu := qu + ';';
	
	WriteLn('TableArpSetStatus(): ', qu);
	
	RunQuery(qu);
end; // of procedure TableArpSetStatus


procedure ActionResetSendmail(recId: integer; curAction: integer; fname: string; upn: string; initpw: string; mailto: string; ref: string);
var
	path: string;
	traceCode: string; // Unique code for this action PRODID+ACTION+REC (147-2-15)
	f: TextFile;
	cmd: Ansistring;
begin
	// Build the path of the e-mail contents file.
	traceCode := IntToStr(PROG_ID) + '-' + IntToStr(curAction) + '-' + IntToStr(recId);
	path := traceCode + '.body';
	
	if FileExists(path) = true then
		DeleteFile(path);
		
	Assign(f, path);
	ReWrite(f);
	
	WriteLn(f, 'Hello ', fname, ',');
	WriteLn(f);
	WriteLn(f, 'The password has been reset for: ', upn);
	WriteLn(f);
	WriteLn(f, 'Initial password:                ' + initpw);
	WriteLn(f);
	WriteLn(f, 'Requested under:                 ', ref);
	WriteLn(f);
	WriteLn(f, 'Trace code: ', traceCode);
	WriteLn(f);
	
	Close(f);
	
	cmd := ' blat.exe ' + path;
	cmd := cmd + ' -to ' + EncloseDoubleQuote(mailto);
	cmd := cmd + ' -f ' + EncloseDoubleQuote(MAIL_FROM);
	cmd := cmd + ' -bcc ' + EncloseDoubleQuote(MAIL_BCC);
	cmd := cmd + ' -subject ' + EncloseDoubleQuote('Password reset done for ' + upn + ' // ' + ref + ' // ADB# ' + traceCode);
	cmd := cmd + ' -server vm70as005.rec.nsint';
	cmd := cmd + ' -port 25';
	
	WriteLn(cmd);
	
	RunCommand(cmd);
	
	// Update the status to 900: Send e-mail
	TableArpSetStatus(recId, 900);
	
	// Delete the body file.
	DeleteFile(path);
end; // of procedure ActionResetSendmail


procedure ActionResetInformByEmail(curAction: integer; recId: integer);
var
	qs: Ansistring;
	rs: TSQLQuery;
	upn: string;
	fname: string;
	mailto: string;
	initpw: string;
	ref: string;
	//recId: integer;
begin
	qs := 'SELECT *';
	qs := qs + ' FROM ' + VIEW_RESET;
	qs := qs + ' WHERE ' + VIEW_RESET_ID + '=' + IntToStr(recId);
	qs := qs + ';';
	
	WriteLn('ActionResetInformByEmail(): ', qs);
	
	rs := TSQLQuery.Create(nil);
	rs.Database := gConnection;
	rs.PacketRecords := -1;
	rs.SQL.Text := qs;
	rs.Open;

	if rs.EOF = true then
		WriteLn('ActionResetInformByEmail(): No records found!')
	else
	begin
		while not rs.EOF do
		begin
			recId := rs.FieldByName(VIEW_RESET_ID).AsInteger;
			upn := rs.FieldByName(VIEW_RESET_UPN).AsString;
			fname := rs.FieldByName(VIEW_RESET_FNAME).AsString;
			mailto := rs.FieldByName(VIEW_RESET_MAIL_TO).AsString;
			initpw := rs.FieldByName(VIEW_RESET_INITPW).AsString;
			ref := rs.FieldByName(VIEW_RESET_REFERENCE).AsString;
			WriteLn('EMAIL CONTENTS: Beste ', fname, ', password reset for ', upn, ' is now set to: ',  initpw, ' (mailto: ', mailto, ')');
			
			ActionResetSendmail(recId, curAction, fname, upn, initpw, mailto, ref);

			rs.Next;
		end;
	end;
	rs.Free;
end; // of procedure ActionResetInformByEmail


procedure ActionResetCheck(curAction: integer; recId: integer; actionSha1: string);	
var
	qs: Ansistring;
	rs: TSQLQuery;
	errorLevel: integer;
	allSuccesFull: boolean;
begin
	qs := 'SELECT ' + FLD_AAD_EL;
	qs := qs + ' FROM ' + TBL_AAD;
	qs := qs + ' WHERE ' + FLD_AAD_ACTION_SHA1 + '=' + EncloseSingleQuote(actionSha1);
	//qs := qs + ' WHERE ' + FLD_AAD_ACTION_NR + '=' + IntToStr(curAction);
	//qs := qs + ' AND ' + FLD_AAD_ACTION_ID + '=' + IntToStr(recId);
	qs := qs + ';';
	
	WriteLn('ActionResetCheck(): ', qs);
	
	rs := TSQLQuery.Create(nil);
	rs.Database := gConnection;
	rs.PacketRecords := -1;
	rs.SQL.Text := qs;
	rs.Open;

	allSuccesFull := true;
	
	if rs.EOF = true then
		WriteLn('ActionResetCheck(): No records found!')
	else
	begin
		while not rs.EOF do
		begin
			errorLevel := rs.FieldByName(FLD_AAD_EL).AsInteger;
			WriteLn(errorLevel:12);
			if errorLevel <> 0 then
			begin
				// Not all steps where successful, set 
				allSuccesFull := false;
			end;
			rs.Next;
		end;
	end;
	rs.Free;
	
	if allSuccesFull = false then
		TableArpSetStatus(recId, 99)
	else
		TableArpSetStatus(recId, 100)
end; // of procedure ActionResetCheck


procedure UpdateAadErrorLevel(recId: integer; errorLevel: integer);
var
	qu: Ansistring;
begin
	qu := 'UPDATE ' + TBL_AAD;
	qu := qu + ' SET';
	qu := qu + ' ' + FLD_AAD_EL + '=' + IntToStr(errorLevel);
	qu := qu + ' WHERE ' + FLD_AAD_ID + '=' + IntToStr(recId);
	qu := qu + ';';
	
	WriteLn('UpdateAadErrorLevel(): ', qu);
	
	RunQuery(qu);
end; // of procedure UpdateAadErrorLevel


procedure ActionResetProcess(curAction: integer; recId: integer; actionSha1: string);
var
	qs: Ansistring;
	rs: TSQLQuery;
	
	cmd: string;
	//upn: string;
	//initialPassword: string;
	//actId: integer;
	//stepNum: integer;
	r: integer;
begin
	WriteLn('PROCESSACTIONS()');
	
	// Select all records where the error level is not filled in,
	// And the is_active field = 9.
	qs := 'SELECT *';
	qs := qs + ' FROM ' + TBL_AAD;
	qs := qs + ' WHERE ' + FLD_AAD_EL + ' IS NULL'; // Error level = 0
	qs := qs + ' AND ' + FLD_AAD_ACTION_SHA1 + '=' + EncloseSingleQuote(actionSha1);
	//qs := qs + ' AND ' + FLD_AAD_ACTION_ID + '=' + IntToStr(recId);
	//qs := qs + ' AND ' + FLD_AAD_ACTION_NR + '=' + IntToStr(curAction);
	qs := qs + ' AND ' + FLD_AAD_IS_ACTIVE + '=' + IntToStr(VALID_ACTIVE);
	qs := qs + ' ORDER BY ' + FLD_AAD_RCD;
	qs := qs + ';';
	
	WriteLn(qs);
	
	rs := TSQLQuery.Create(nil);
	rs.Database := gConnection;
	rs.PacketRecords := -1;
	rs.SQL.Text := qs;
	rs.Open;

	if rs.EOF = true then
		WriteLn('ProcessActions(): No records found!')
	else
	begin
		while not rs.EOF do
		begin
			recId := rs.FieldByName(FLD_AAD_ID).AsInteger;
			cmd := rs.FieldByName(FLD_AAD_CMD).AsString;
			
			WriteLn(recId:4, '     ', cmd);
			
			r := RunCommand(cmd);
			WriteLn('RunCommand: ', cmd);
			WriteLn('ERRORLEVEL=' , r);
			
			UpdateAadErrorLevel(recId, r);
			
			rs.Next;
		end;
	end;
	rs.Free;
end; // of procedure ProcessActions


{
procedure UpdatePassword(recId: integer; newPassword: string);
var
	qu: Ansistring;
begin
	qu := 'UPDATE ' + VIEW_RESET;
	qu := qu + ' SET';
	qu := qu + ' ' + VIEW_RESET_INITPW + '=' + EncloseSingleQuote(newPassword);
	qu := qu + ' WHERE ' + VIEW_RESET_ID + '=' + IntToStr(recId);
	qu := qu + ';';
	
	//WriteLn('UpdatePassword(): ', qu);
	RunQuery(qu);
end; // of procedure UpdatePassword
}


{
procedure UpdateActionSha1(recId: integer; newActionSha1: string);
var
	qu: Ansistring;
begin
	qu := 'UPDATE ' + VIEW_RESET;
	qu := qu + ' SET';
	qu := qu + ' ' + VIEW_RESET_ACTION_SHA1 + '=' + EncloseSingleQuote(newActionSha1);
	qu := qu + ' WHERE ' + VIEW_RESET_ID + '=' + IntToStr(recId);
	qu := qu + ';';
	
	//WriteLn('UpdateActionSha1(): ', qu);
	RunQuery(qu);
end; // of procedure UpdateActionSha1
}

procedure DoActionReset(curAction: integer);
//
//		curAction		What is the current action (2 for password reset)
//
var
	qs: Ansistring;
	rs: TSQLQuery;
	c: Ansistring;
	recId: integer;
	dn: string;
	upn: string;
	initialPassword: string;
	actionSha1: string; // Unique Action SHA1 number: 4a540008e0a05425b79ccefb1086dff5d18a6f4b (a 40 chars Hex number)
begin
	WriteLn('-----------------------------------------------------------------');
	WriteLn('DOACTIONRESET(', curAction, ')');
	
	qs := 'SELECT * ';
	qs := qs + 'FROM ' + VIEW_RESET + ' ';
	qs := qs + 'WHERE ' + VIEW_RESET_IS_ACTIVE + '=' + IntToStr(VALID_ACTIVE) + ' ';
	qs := qs + 'AND ' + VIEW_RESET_STATUS + '=0 ' ;
	qs := qs + 'ORDER BY ' + VIEW_RESET_RCD;
	qs := qs + ';';
	
	//WriteLn(qs);
	
	rs := TSQLQuery.Create(nil);
	rs.Database := gConnection;
	rs.PacketRecords := -1;
	rs.SQL.Text := qs;
	rs.Open;

	if rs.EOF = true then
		WriteLn('No records found!')
	else
	begin
		while not rs.EOF do
		begin
			recId := rs.FieldByName(VIEW_RESET_ID).AsInteger;
			dn := rs.FieldByName(VIEW_RESET_DN).AsString;
			upn := rs.FieldByName(VIEW_RESET_UPN).AsString;
			initialPassword := rs.FieldByName(VIEW_RESET_INITPW).AsString;
			
			if Length(initialPassword) = 0 then
			begin
				// When no initial password is entered in the table, generate a new password
				initialPassword := GeneratePassword();
				
				// Update the table to register the generated password. 
				//UpdatePassword(recId, initialPassword);
				UpdateOneFieldString(VIEW_RESET, VIEW_RESET_ID, recId, VIEW_RESET_INITPW, initialPassword);
				
			end; // of if
			
			actionSha1 := GenerateUniqueActionNumber(curAction);
			WriteLn('Unique SHA1 for this specific action: ', actionSha1);
			//UpdateActionSha1(recId, actionSha1);
			UpdateOneFieldString(VIEW_RESET, VIEW_RESET_ID, recId, VIEW_RESET_ACTION_SHA1, actionSha1);
				
			WriteLn(recId:4, ' ', dn, '  ', upn, '  ', initialPassword);
			
			// Add the first step: Write the command to the action_do table to setup a new password.
			c := 'dsmod.exe user ' + EncloseDoubleQuote(dn) + ' -pwd ' + EncloseDoubleQuote(initialPassword);
			AddRecordToTableAad(actionSha1, c);
			
			// Set the 2nd step: Write the command to "Must change password flag on".
			c :=  'dsmod.exe user ' + EncloseDoubleQuote(dn) + ' -mustchpwd yes';
			AddRecordToTableAad(actionSha1, c);
			
			if IsAccountLockedout(dn) = true then
			begin
				// If the account is locked out, use DSMOD USER <dn> -disabled no to unlock.
				c :=  'dsmod.exe user ' + EncloseDoubleQuote(dn) + ' -disabled no';
				AddRecordToTableAad(actionSha1, c);
			end;
			
			// Execute all actions in table AAD for password resets
			//ActionResetProcess(curAction, recId, actionSha1);
			TableAadProcessActions(actionSha1);

			// Check all records that are processed for a correct execution
			ActionResetCheck(curAction, recId, actionSha1);
			
			// Send a e-mail to the requester with the password.
			ActionResetInformByEmail(curAction, recId);
			
			rs.Next;
		end;
	end;
	rs.Free;
end; // of procedure ActionResetFillTableAad


end. // of unit aam_action_reset