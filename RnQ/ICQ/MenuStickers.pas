{
  This file is part of R&Q.
  Under same license
}
unit MenuStickers;
{$I RnQConfig.inc}
{$I NoRTTI.inc}

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Types, StdCtrls, RnQNet, RnQProtocol, utilLib,
  ExtCtrls, RDGlobal, RnQGraphics32, RnQButtons, AwImageGrid,
  System.Threading, System.SyncObjs, System.Actions, Vcl.ActnList, Generics.Collections;

type
  TFStickers = class(TForm)
    exts: TPanel;
    scrollLeft: TRnQSpeedButton;
    scrollRight: TRnQSpeedButton;
    actList: TActionList;
    NextExt: TAction;
    PrevExt: TAction;
    UpdTmr: TTimer;
    procedure FormShow(Sender: TObject);
    procedure UpdTmrTimer(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCreate(Sender: TObject);
    procedure FormPaint(Sender: TObject);
    procedure showStickerExt(ext: Integer);
    procedure OnExtBtnClick(Sender: TObject);
    procedure InvalidateSticker(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure SendSelectedSticker(Sender: TCustomImageGrid; Index: Integer);
    procedure SendSticker(StickerMsg: String; Index: Integer);
    procedure scrollLeftClick(Sender: TObject);
    procedure scrollRightClick(Sender: TObject);
    procedure RecreateExtBtns;
    procedure RefreshExtBtnStates;
    procedure FormHide(Sender: TObject);
    procedure NextExtExecute(Sender: TObject);
    procedure PrevExtExecute(Sender: TObject);
  private
    { Private declarations }
    DrawLines, DrawStickers : Integer;
    curHint: String;
  public
    { Public declarations }
    procedure CreateParams( var Params: TCreateParams );override;
  end;
  procedure ShowStickersMenu(rnqcon: TRnQContact; t: tpoint);

var
  rnqContact: TRnQContact;
  FStickers: TFStickers;
  StickerToken : Integer;
  prefBtnWidth, prefBtnHeight : Integer;
  prefSmlAutoSize : Boolean;
  DrawStickerGrid : Boolean;

implementation

{ $R 'stickers.res' 'stickers.rc'} // Added to Project Source

uses
  ICQv9, ICQ.Stickers,
  RnQLangs, RnQGlobal, RQUtil, RQThemes,
  events, history,
  chatDlg, globalLib;

var
  stickerGrids: TDictionary<Integer, TAwImageGrid>;
  initialized: Boolean = False;
  extPos: Integer = 1;
  openedExt: Integer = 1;

const
  stickerWidth: Integer = 120;
  stickerHeight: Integer = 120;
  stickerExtNames: array [1..30] of Integer =
  (1,  2,  79, 80, 81, 87, 95, 97, 106, 107, 109, 111, 112, 113, 118, 119, 121, 123, 124, {149,} 151, 157, 158, 180, 203, 205, 209, 211, 213, 217, 108);
  stickerExtCounts: array [1..30] of Integer =
  (26, 36, 10, 10, 10, 8,  25, 10, 10,  10,  36,  20,  20,  24,  24,  24,  24,  8,   24,  {24,}  20,  60,  30,  40,  16,  8,   16,  50,  24,  20,  8);
  stickerExtHints: array [1..30] of String = (
    'Pandas', 'Whiskers', 'Super Joe', 'Kittens', 'Holiday Cake', 'Smurfs', 'Memes', 'Bro', 'Boomz Man', 'Boomz Girl',
    'Crackers', 'Chickens', 'Horror', 'Holiday Cards', 'I Love You', 'Supercharged stickers', 'Obrigado, Brasil!',
    'Onca', 'Russian words', 'Bate-papo maneiro', 'Emoticons', 'Paranormal Love', 'Warm Together', 'Just in case',
    'Nauryz', 'Spring festivities', 'Nichosi-meme', 'Snob Dog', 'Sonya', 'Musical Cat'
  );

{$R *.dfm}

procedure GoToChat;
begin
  SetForegroundWindow(chatFrm.Handle);
end;

procedure TFStickers.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  with Params do
  begin
    Style := Style or WS_OVERLAPPED;
    Style := Style and not WS_CLIPCHILDREN;
    WndParent := chatFrm.Handle;
    ExStyle := ExStyle or WS_EX_LAYERED;
  end;
end;

procedure TFStickers.FormShow(Sender: TObject);
begin
  showStickerExt(openedExt);
end;

procedure TFStickers.UpdTmrTimer(Sender: TObject);
begin
  if GetForegroundWindow <> self.Handle then
  begin
    Self.Hide;
    UpdTmr.Enabled := False;
  end;
end;

procedure getStickerAsync(FExt, FSticker: Integer);
var
  fs: TMemoryStream;
  png: TRnQBitmap;
  stickerGrid: TAwImageGrid;
  url, fn: String;
  Task: ITask;
begin
  TThreadPool.Default.SetMinWorkerThreads(3);
  TThreadPool.Default.SetMaxWorkerThreads(5);
  Task := TTask.Create(procedure()
  begin
    png := TRnQBitmap.Create;
    fs := TMemoryStream.Create;

    getSticker(IntToStr(stickerExtNames[FExt]), IntToStr(FSticker), @fs, 'small');
    if loadPic(TStream(fs), png) then
//    if not png.Empty then
      begin
  //      if (png.Header.ColorType = COLOR_PALETTE) then
  //        ConvertToRGBA(png);
        stickerGrid := stickerGrids.Items[FExt];
        if not (stickerGrid = nil) then
          stickerGrid.Items.AddThumb('ext:' + IntToStr(stickerExtNames[FExt]) + ':sticker:' + IntToStr(FSticker), png);
        if FSticker = stickerExtCounts[FExt] then
        begin
  //        fStickers.loderPanel.Hide;
          stickerGrid.Items.EndUpdate;
        end;
      end
    else
     begin
      fs.Free;
      png.Free;
     end;
  end, TThreadPool.Default);
  task.Start;
end;

procedure TFStickers.showStickerExt(ext: Integer);
var
  stickerGrid: TAwImageGrid;
  i: Integer;
begin
  if not stickerGrids.ContainsKey(ext) then
  begin
    stickerGrid := TAwImageGrid.Create(self);
    stickerGrid.Width := 0;
    stickerGrid.Height := 0;
    stickerGrid.Parent := Self;
    stickerGrid.DoubleBuffered := True;
    stickerGrid.Align := alClient;
    stickerGrid.AlignWithMargins := True;
    stickerGrid.Margins.Top := 7;
    stickerGrid.Margins.Left := 7;
    stickerGrid.Margins.Right := 1;
    stickerGrid.Margins.Bottom:= 3;

    stickerGrid.AutoHideScrollBar := True;
    stickerGrid.BorderStyle := bsNone;
    stickerGrid.CellAlignment := taCenter;
    stickerGrid.CellLayout := tlCenter;
    stickerGrid.CellHeight := stickerHeight;
    stickerGrid.CellWidth := stickerWidth;
    stickerGrid.CellSpacing := 0;
    stickerGrid.Color := clBtnFace;
    stickerGrid.WheelScrollLines := 1;
    stickerGrid.Sorted := True;
    stickerGrid.DragScroll := False;
    stickerGrid.MarkerStyle := psClear;
    stickerGrid.Cursor := crHandPoint;

    stickerGrid.OnMouseDown := InvalidateSticker;
    stickerGrid.OnMouseUp := InvalidateSticker;
    stickerGrid.OnClickCell := SendSelectedSticker;
    stickerGrids.AddOrSetValue(ext, stickerGrid);

    stickerGrid.Items.BeginUpdate;
{
    loderPanel.Left := Round(fStickers.Width / 2 - loderPanel.Width / 2);
    loderPanel.Top := Round(fStickers.Height / 2 - loderPanel.Height / 2 + exts.Height / 2);
    loderPanel.Show;
}
    for i := 1 to stickerExtCounts[ext] do
      getStickerAsync(ext, i);
  end
    else
  stickerGrid := stickerGrids.Items[ext];

  stickerGrid.BringToFront;
//  loderPanel.BringToFront;
  stickerGrid.SetFocus;
  openedExt := ext;
  UpdTmr.Enabled := True;
end;

procedure TFStickers.InvalidateSticker(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  (Sender as TAwImageGrid).Invalidate;
end;

procedure TFStickers.NextExtExecute(Sender: TObject);
begin
  if openedExt >= High(stickerExtNames) then
  begin
    openedExt := Low(stickerExtNames);
    extPos := Low(stickerExtNames);
    RecreateExtBtns;
  end
    else
  inc(openedExt);

  if openedExt >= extPos + 9 then
  begin
    inc(extPos, 9);
    RecreateExtBtns;
  end
    else
  RefreshExtBtnStates;

  showStickerExt(openedExt);
end;

procedure TFStickers.SendSticker(StickerMsg: String; Index: Integer);
var
  ev: Thevent;
  extStiker: TStringList;
begin
  if OnlFeature(rnqContact.fProto) then
  begin
    Self.Hide;
    GoToChat;

    TICQSession(rnqContact.fProto).sendSticker(rnqContact.UID, StickerMsg);

    // Add sticker to chat
    extStiker := TStringList.Create;
    extStiker.Delimiter := ':';
    extStiker.StrictDelimiter := true;
    extStiker.DelimitedText := StickerMsg;
    ev := Thevent.new(EK_MSG, rnqContact.fProto.getMyInfo, Now, getSticker(extStiker.Strings[1], extStiker.Strings[3])
                      {$IFDEF DB_ENABLED}, ''{$ENDIF DB_ENABLED}, 0);
    ev.fIsMyEvent := True;
    writeHistorySafely(ev, rnqContact);
    chatFrm.addEvent(rnqContact, ev.clone);
    ev.Free;
    extStiker.Free;
  end
    else
  Self.Hide
end;

procedure TFStickers.SendSelectedSticker(Sender: TCustomImageGrid; Index: Integer);
begin
  SendSticker((Sender as TAwImageGrid).FileNames[Index], Index);
end;

procedure TFStickers.RecreateExtBtns();
var
  i: Integer;
  extBtn: TRnQSpeedButton;
  AlphaTask: ITask;
begin
  for i := exts.ComponentCount - 1 downto 0 do
    if exts.Components[i] is TRnQSpeedButton then
      if (exts.Components[i] as TRnQSpeedButton).Tag > 0 then
        exts.Components[i].Free;

  for i := extPos to extPos + 8 do
  if i <= High(stickerExtNames) then
  begin
    extBtn := TRnQSpeedButton.Create(exts);
    extBtn.Parent := exts;
    extBtn.Left := exts.Width;
    extBtn.Align := alLeft;
    extBtn.AlignWithMargins := true;
    extBtn.AllowAllUp := True;
    extBtn.Flat := True;
    extBtn.Margins.Bottom := 5;
    extBtn.Margins.Left := 9;
    extBtn.Margins.Right := 0;
    extBtn.Margins.Top := 5;
    extBtn.Spacing := 0;
    extBtn.Transparent := True;
    extBtn.Width := 42;
    extBtn.ImageName := 'sticker' + IntToStr(stickerExtNames[i]);
    extBtn.Tag := i;
    extBtn.OnClick := OnExtBtnClick;
    extBtn.Cursor := crHandPoint;
    extBtn.Hint := GetTranslation(stickerExtHints[i]);
    extBtn.ShowHint := false;
    RefreshExtBtnStates;

    if i = extPos then
      extBtn.Margins.Left := 30;

    if (extPos = 1) then
    begin
      scrollLeft.ImageName := 'arrow_left_dis';
      scrollLeft.Enabled := False;
    end
      else
    begin
      scrollLeft.ImageName := 'arrow_left';
      scrollLeft.Enabled := True;
    end;

    if (extPos >= 28) then
    begin
      scrollRight.ImageName := 'arrow_right_dis';
      scrollRight.Enabled := False;
    end
      else
    begin
      scrollRight.ImageName := 'arrow_right';
      scrollRight.Enabled := True;
    end;
  end;
end;

procedure TFStickers.FormCreate(Sender: TObject);
var
  a: Integer;
begin
  initialized := False;
{
  (loader.Picture.Graphic as TGIFImage).Animate := True;
  (loader.Picture.Graphic as TGIFImage).AnimationSpeed := 130;
}
  stickerGrids := TDictionary<Integer, TAwImageGrid>.Create;
  RecreateExtBtns;

  scrollLeft.ImageName := 'arrow_left_dis';
  scrollLeft.Left := -1;
  scrollLeft.Top := -1;
  scrollLeft.Height := exts.Height + 2;
  scrollLeft.Width := 21;

  scrollRight.ImageName := 'arrow_right';
  scrollRight.Width := 21;
  scrollRight.Left := (stickerWidth + 8) * 4 - scrollRight.Width - 1;
  scrollRight.Top := -1;
  scrollRight.Height := exts.Height + 2;

  for a in stickerExtNames do
   begin
//     theme.AddPicResource('sticker' + IntToStr(a), 'STICKER' + IntToStr(a))
     theme.AddPicResource('sticker' + IntToStr(a), 'sticker' + IntToStr(a))
   end;
end;

procedure TFStickers.FormHide(Sender: TObject);
var
  pair: TPair<Integer, TAwImageGrid>;
begin
//  EnableStickersCache := MainPrefs.getPrefBoolDef('chat-images-enable-stickers-cache', True);
  if MainPrefs.getPrefBoolDef('chat-images-enable-stickers-cache', True) then
  for pair in stickerGrids do
  if Assigned(pair.Value) then
  if not (pair.Key = openedExt) then
  begin
    pair.Value.Free;
    stickerGrids.Remove(pair.Key);
  end;
end;

procedure TFStickers.OnExtBtnClick(Sender: TObject);
begin
  showStickerExt((Sender as TRnqSpeedButton).Tag);
  RefreshExtBtnStates;
end;

procedure TFStickers.PrevExtExecute(Sender: TObject);
begin
  if openedExt <= Low(stickerExtNames) then
  begin
    openedExt := High(stickerExtNames);
    extPos := (High(stickerExtNames) div 9) * 9 + 1;
    RecreateExtBtns;
  end
    else
  dec(openedExt);

  if openedExt < extPos then
  begin
    dec(extPos, 9);
    RecreateExtBtns;
  end
    else
  RefreshExtBtnStates;

  showStickerExt(openedExt);
end;

procedure TFStickers.RefreshExtBtnStates;
var
  i: Integer;
  btn: TRnQSpeedButton;
begin
  for i := exts.ComponentCount - 1 downto 0 do
    if exts.Components[i] is TRnQSpeedButton then
    begin
      btn := exts.Components[i] as TRnQSpeedButton;
      if btn.Tag = openedExt then
        btn.FState := bsExclusive
      else
        btn.FState := bsUp;
      btn.Invalidate;
    end;
end;

procedure TFStickers.scrollLeftClick(Sender: TObject);
begin
  if (extPos > 9) then
  begin
    dec(extPos, 9);
    RecreateExtBtns;
  end;
end;

procedure TFStickers.scrollRightClick(Sender: TObject);
begin
  if (extPos < 28) then
  begin
    inc(extPos, 9);
    RecreateExtBtns;
  end;
end;

procedure TFStickers.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Index: Integer;
begin
  case key of
    VK_ESCAPE:
    begin
      Self.Hide;
      GoToChat;
    end;
    VK_RETURN, VK_SPACE:
    begin
      Index := stickerGrids.Items[openedExt].ItemIndex;
      if (Index >= 0) and (Index < stickerGrids.Items[openedExt].Count) then
      sendSticker(stickerGrids.Items[openedExt].FileNames[Index], Index);
    end;
  end;
end;

procedure TFStickers.FormPaint(Sender: TObject);
var
  DC: HDC;
  Rgn: HRGN;
  brF : HBRUSH;
begin
  inherited;
  DC := GetDCEx(Handle, 0, DCX_PARENTCLIP);
  Rgn := CreateRectRgn(ClientRect.Left, ClientRect.Top, ClientRect.Right, ClientRect.Bottom);
  SelectClipRgn(DC, Rgn);
  DeleteObject(Rgn);

  SelectObject(DC, GetStockObject(DC_BRUSH));

  brF := CreateSolidBrush(ColorToRGB(clSilver));
  FrameRect(Canvas.Handle, Rect(0, 0, Self.Width, Self.Height), brF);
  FrameRect(Canvas.Handle, Rect(0, 0, Self.Width, exts.Height + 2), brF);
  DeleteObject(brF);

  ReleaseDC(Handle, DC);
end;

procedure ShowStickersMenu(rnqcon: TRnQContact; t: tpoint);
var
  ar: array[1..4] of TRect;
  scr, intr, a: Trect;
  i, p1, p2: integer;
begin
  rnqContact := rnqcon;

  if not Assigned(fStickers) then
    fStickers := TFStickers.Create(nil);
  fStickers.Height := (stickerHeight + 5) * 3 + fStickers.exts.Height;
  fStickers.Width := (stickerWidth + 8) * 4;

  scr := Screen.MonitorFromPoint(t).WorkareaRect;
  ar[1] := Rect(t.X, t.Y - fStickers.Height, t.X + fStickers.Width, t.Y);
  ar[2] := Rect(t.X - fStickers.Width, t.Y - fStickers.Height, t.X, t.Y);
  ar[3] := Rect(t.X, t.Y, t.X + fStickers.Width, t.Y + fStickers.Height);
  ar[4] := Rect(t.X - fStickers.Width, t.Y, t.X, t.Y + fStickers.Height);
  a := Rect(0, 0, 0, 0);

  for i := 1 to 4 do
  begin
    Types.IntersectRect(intr, ar[i], scr);
    p1 := (intr.Right - intr.Left) * (intr.Bottom - intr.Top);
    p2 := (a.Right - a.Left) * (a.Bottom - a.Top);
    if p1 > p2 then
    begin
      a := intr;
      fStickers.Top := ar[i].Top;
      fStickers.Left := ar[i].Left;
    end;
  end;

  FStickers.Show;
end;

procedure Add2input(const s: String);
begin
  chatFrm.thisChat.input.SelText := s;
end;

end.
