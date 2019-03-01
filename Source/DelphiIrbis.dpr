library DelphiIrbis;

{$WARN UNSAFE_CODE OFF}
{$WARN UNSAFE_TYPE OFF}

uses
  ShareMem, SysUtils, Classes, Sockets;

//=========================================================

procedure WriteAnsi(stream: TStream; ws: WideString); stdcall; export;
var
   us: AnsiString;
begin
  us:=ws;
  stream.Write(us[1], Length(us));
end;

procedure WriteUtf8(stream: TStream; ws: WideString); stdcall; export;
var
   us: Utf8String;
begin
  us:=UTF8Encode(ws);
  stream.Write(us[1], Length(us));
end;

//=========================================================

// forward declarations

type IrbisConnection = class;

//=========================================================

SubField = class
public
  Code  : Char;
  Value : WideString;
end;

//=========================================================

RecordField = class
public
  Tag       : Integer;
  Value     : WideString;
  Subfields : TList;

  constructor Create;
  destructor Destroy; override;
end;

//=========================================================

MarcRecord = class
public
  Database  : String;
  Mfn       : Integer;
  Status    : Integer;
  Version   : Integer;
  Fields    : TList;

  constructor Create;
  destructor  Destroy; override;
end;

//=========================================================

ClientQuery = class
private
  _connection: IrbisConnection;
  _stream: TMemoryStream;

public
  constructor Create(connection: IrbisConnection; command: AnsiString);
  destructor Destroy; override;

  property Bytes: TMemoryStream  read _stream;

  function Add(value: Integer): ClientQuery;
  function AddAnsi(text: WideString): ClientQuery;
  function AddUtf(text: WideString): ClientQuery;
  function NewLine: ClientQuery;
end;

//=========================================================

ServerResponse = class
private
  _stream: TMemoryStream;

public
  Command    : String;
  ClientId   : Integer;
  QueryId    : Integer;
  ReturnCode : Integer;

  constructor Create(socket: TTcpClient);
  destructor Destroy; override;

  procedure CheckReturnCode;
  function ReadAnsi: WideString;
  function ReadInteger: Integer;
  function ReadUtf: WideString;
end;

//=========================================================

IrbisConnection = class
private
  _clientID   : Integer;
  _queryID    : Integer;
  _connected  : Boolean;

public
  Host        : WideString;
  Port        : TSocketPort;
  Username    : WideString;
  Password    : WideString;
  Database    : WideString;
  Workstation : WideString;

  property Connected: Boolean  read _connected;

  constructor Create;
  destructor  Destroy; override;

  procedure Connect;
  procedure Disconnect;
  function Execute(query: ClientQuery): ServerResponse;
  function GetMaxMfn(database: string): Integer;
  procedure NoOp;
end;

//=========================================================

constructor RecordField.Create;
begin
  Subfields := TList.Create;
end;

destructor RecordField.Destroy;
begin
  Subfields.Destroy;
end;

constructor MarcRecord.Create;
begin
  Fields := TList.Create;
end;

destructor MarcRecord.Destroy;
begin
  Fields.Destroy;
end;

constructor ClientQuery.Create(connection: IrbisConnection;
  command: AnsiString);
begin
  _connection := connection;
  _stream := TMemoryStream.Create;

  AddAnsi(command).NewLine;
  AddAnsi(connection.Workstation).NewLine;
  AddAnsi(command).NewLine;
  Add(connection._clientID).NewLine;
  Add(connection._queryID).NewLine;
  AddAnsi(connection.Password).NewLine;
  AddAnsi(connection.Username).NewLine;
  NewLine;
  NewLine;
  NewLine;
end;

destructor ClientQuery.Destroy;
begin
  _stream.Destroy;
end;

function ClientQuery.Add(value: Integer): ClientQuery;
begin
  AddAnsi(IntToStr(value));
  Result := Self;
end;

function ClientQuery.AddAnsi(text: WideString): ClientQuery;
begin
  WriteAnsi(_stream, text);
  Result := Self;
end;

function ClientQuery.AddUtf(text: WideString): ClientQuery;
begin
  WriteUtf8(_stream, text);
  Result := Self;
end;

function ClientQuery.NewLine: ClientQuery;
var
  nl : array[0..1] of Char;
begin
  nl[0] := #10;
  _stream.Write(nl, 1);
  Result := Self;
end;

constructor ServerResponse.Create(socket: TTcpClient);
var
  buffer: array[0.. 2047] of Byte;
  i, received: Integer;
begin
  _stream := TMemoryStream.Create;

  while True do
  begin
    received := socket.ReceiveBuf(buffer, 2048);
    if received = 0 then Break;
    _stream.WriteBuffer(buffer, received);
  end;

  _stream.Position := 0;

  Command := ReadAnsi;
  ClientId := ReadInteger;
  QueryId := ReadInteger;

  for i:=0 to 6 do
    ReadAnsi;

end;

destructor ServerResponse.Destroy;
begin
  _stream.Destroy;
end;

procedure ServerResponse.CheckReturnCode;
begin
  // TODO
  ReturnCode := 0;
end;

function ServerResponse.ReadAnsi: WideString;
begin
  // TODO
  Result := '';
end;

function ServerResponse.ReadInteger: Integer;
begin
  // TODO
  Result := 0;
end;

function ServerResponse.ReadUtf: WideString;
begin
  // TODO
  Result := '';
end;

//=========================================================

constructor IrbisConnection.Create;
begin
  Host        := 'localhost';
  Port        := '6666';
  Workstation := 'C';
  Database    := 'IBIS';
  _connected  := False;
end;

destructor IrbisConnection.Destroy;
begin
  Disconnect;
end;

function IrbisConnection.Execute(query: ClientQuery): ServerResponse;
var
  socket: TTcpClient;
begin
  socket := TTcpClient.Create(nil);
  socket.RemoteHost := Host;
  socket.RemotePort := Port;
  if not socket.Connect then
  begin
    socket.Destroy;
    Result := nil;
    Exit;
  end;

  socket.SendStream(query.Bytes);
  Result := ServerResponse.Create(socket);
  socket.Close;

  _queryID := _queryID + 1;
end;

procedure IrbisConnection.Connect;
var
  query: ClientQuery;
  response: ServerResponse;
begin
  if Connected then Exit;

  _clientID := 100000 + Random(800000);
  _queryID  := 1;
  query := ClientQuery.Create(Self, 'A');
  query.AddAnsi(Username).NewLine;
  query.AddAnsi(Password).NewLine;
  response := Execute(query);
  query.Destroy;
  response.Destroy;

  _connected := True;
end;

procedure IrbisConnection.Disconnect;
var
  query: ClientQuery;
  response: ServerResponse;
begin
  if not Connected then Exit;

  query := ClientQuery.Create(Self, 'B');
  query.AddAnsi(Username);
  response := Execute(query);
  query.Destroy;
  response.Destroy;

  _connected := False;
end;

function IrbisConnection.GetMaxMfn(database: String): Integer;
var
  query: ClientQuery;
  response: ServerResponse;
begin
  query := ClientQuery.Create(Self, 'O');
  query.AddAnsi(Database);
  response := Execute(query);
  response.CheckReturnCode;
  Result := response.ReturnCode;
  query.Destroy;
  response.Destroy;
end;

procedure IrbisConnection.NoOp;
var
  query: ClientQuery;
  response: ServerResponse;
begin
  query := ClientQuery.Create(Self, 'N');
  response := Execute(query);
  query.Destroy;
  response.Destroy;
end;

//=========================================================

{$R *.res}

exports

WriteAnsi name 'WriteAnsi',
WriteUtf8 name 'WriteUtf8';

begin
end.
