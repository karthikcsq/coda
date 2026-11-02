"""Synthetic, offline formatter latency probe. No audio, clipboard or app context."""
import argparse,json,pathlib,statistics,subprocess,time

FAST_CASES=[
 ('short-correction','Send the package on Monday actually Thursday.'),
 ('short-layout','hello Anika comma new paragraph please review the invoice period'),
 ('plain-80',('We should keep the current plan and every small detail. '*8).strip()),
 ('correction-80',('We should keep the current plan and every small detail. '*8)+'Send it on Monday actually Thursday.'),
 ('correction-200',('We should keep the current plan and every small detail. '*20)+'Send it on Monday actually Thursday.'),
 ('plain-200',('We should keep the current plan and every small detail. '*20).strip()),
 ('long-list','shopping list colon '+ ' comma '.join(['apples','pears','rice','socks','books','pens','paper','soap','salt','tea','bread','milk'])),
]
MODEL_CASES=[
 ('plain-unpunctuated','please leave the parcel near the smaller entrance tomorrow'),
 ('grammar-unpunctuated',"we was there and she don't know"),
 ('fillers-unpunctuated','um I think perhaps we could really really wait until tomorrow'),
 ('ordinary-cue','They actually said no'),
 ('different-context','Zarina will visit us after the market closes tomorrow'),
 ('long-unpunctuated','At the morning workshop the team reviews the current schedule and compares several practical options for the coming season everyone brings a notebook and a printed map of the neighborhood the discussion starts with transport then moves toward seating refreshments invitations and volunteer responsibilities after a short break the coordinator checks the supply cabinet while another participant measures the doorway near the entrance a visitor suggests placing the welcome table beside the large window because the afternoon sunlight makes that corner easier to find meanwhile the remaining members arrange chairs around the central display and leave enough space for people carrying bags before leaving they check the weather forecast confirm the delivery address and agree to send a brief update tomorrow nobody needs to change the budget today but the final order should wait until the attendance estimate arrives later this week several people offer to return early on Saturday to help prepare the room and label the storage boxes'),
]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--worker',type=pathlib.Path,default=pathlib.Path(__file__).with_name('worker.py'))
    parser.add_argument('--output',type=pathlib.Path,required=True)
    parser.add_argument('--model-cases',action='store_true')
    args=parser.parse_args();base=pathlib.Path.home()/'Library/Application Support/Coda/SmartCleanup/v1'
    start=time.perf_counter()
    process=subprocess.Popen([str(base/'runtime/bin/python'),str(args.worker),str(base/'model')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
    try:
        assert json.loads(process.stdout.readline()).get('ready')
        ready=time.perf_counter()-start; rows=[]
        for repeat in range(2):
            for name,raw in MODEL_CASES if args.model_cases else FAST_CASES:
                start=time.perf_counter();process.stdin.write(json.dumps({'id':name,'text':raw})+'\n');process.stdin.flush()
                row=json.loads(process.stdout.readline())
                while row.get('ready'):row=json.loads(process.stdout.readline())
                assert row.get('id')==name
                row.update(case=name,raw=raw,repeat=repeat,wall_seconds=time.perf_counter()-start)
                assert row.get('accepted') or row.get('text')==raw
                rows.append(row)
                print(name,repeat,round(row['wall_seconds']*1000,3),row.get('accepted'),row.get('reason'),flush=True)
        summary=dict(ready_seconds=ready,median_seconds=statistics.median(r['wall_seconds'] for r in rows),max_seconds=max(r['wall_seconds'] for r in rows))
        args.output.write_text(json.dumps(dict(summary=summary,rows=rows),indent=2,ensure_ascii=False)+'\n')
        print(json.dumps(summary),flush=True)
    finally:
        process.stdin.close()
        try:process.wait(timeout=15)
        except subprocess.TimeoutExpired:process.kill();process.wait()

if __name__=='__main__':main()
