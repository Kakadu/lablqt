#include "headers.h"
#include "enums.h"
#include <caml/mlvalues.h>
#include <stdio.h>
#include <QtGui/QWidget>
#include "AA.h"

void QWidget_twin::call_super_keyPressEvent(QKeyEvent *ev) {
  foo(1);
  QWidget::keyPressEvent(ev);
}
void QWidget_twin::foo(int x) {
  if (x>0)
    foo(x-1);
  else 
    return;
}
void QWidget_twin::keyPressEvent(QKeyEvent *ev) {
    CAMLparam0();
    CAMLlocal3(meth,camlobj,_ev);
    GET_CAML_OBJECT(this,the_caml_object);
    camlobj = (value)the_caml_object;
    printf ("inside QWidget_twin::keyPressedEvent, camlobj = %x\n", camlobj);
    meth = caml_get_public_method( camlobj, caml_hash_variant("keyPressEvent"));
    if (meth==0)
      printf ("total fail\n");
    printf ("tag of meth is %d\n", Tag_val(meth) );
    printf("calling callback of meth = %x\n",meth);
    setAbstrClass(_ev,QKeyEvent,ev);
    caml_callback2(meth, camlobj, _ev);
    printf ("exit from QWidget_twin::keyPressedEvent\n");
    CAMLreturn0;
}

extern "C" {
CAMLprim
value create_QWidget_twin(value arg0) {
  CAMLparam1(arg0);
  CAMLlocal1(ans);
  QWidget* _arg0 = (arg0==Val_none) ? NULL : QWidget_val(arg0);
  QWidget_twin *_ans = new QWidget_twin(_arg0);
  setAbstrClass(ans,QWidget,_ans);
  printf("QWidget_twin created: %x, abstr = %x \n", _ans, ans);
  CAMLreturn(ans);
}
CAMLprim
value qWidget_twin_super_keyPressEvent(value self,value arg0) {
  CAMLparam2(self,arg0);
  printf("inside qWidget_twin_super_keyPressEvent\n");
  QWidget_twin *_self = QWidget_twin_val(self);
  QKeyEvent* _arg0 = QKeyEvent_val(arg0);
  printf ("keyEvent parameter = %d\n", _arg0);
  _self -> call_super_keyPressEvent(_arg0);
  CAMLreturn(Val_unit);
}
CAMLprim
value qWidget_twin_show(value self) {
  CAMLparam1(self);
  QWidget_twin *_self = QWidget_twin_val(self);
  _self -> show();
  CAMLreturn(Val_unit);
}

}
