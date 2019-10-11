docker run -it --name tournament-test --net cartesi-network --ip 172.18.0.21 -p 127.0.0.1:3001:3001 --rm cartesi/image-tournament-test bash -c "export RUST_LOG=dispatcher=trace,transaction=trace,configuration=trace,utils=trace,state=trace,compute=trace,hasher=trace,logger_test=trace && export CARTESI_CONCERN_KEY=0x94229cae78fdc54ba605b2173fcf7034387bfe5fac37148e3f4badb20aa13e5c && mkdir -p /opt/cartesi/working_path && cat /opt/cartesi/dispatcher_config_0.yaml && cargo run -- --config_path /opt/cartesi/dispatcher_config_0.yaml --working_path /opt/cartesi/working_path"

