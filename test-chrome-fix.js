// Chrome地理位置修复测试脚本
// 在浏览器控制台中运行此脚本来测试地理位置功能

console.log('🔧 Chrome地理位置修复测试开始...');

// 检查基本环境
function checkEnvironment() {
    console.log('📋 环境检查:');
    console.log('- 用户代理:', navigator.userAgent);
    console.log('- 协议:', location.protocol);
    console.log('- 主机名:', location.hostname);
    console.log('- 地理位置支持:', !!navigator.geolocation);
    console.log('- 是否Chrome:', /Chrome/.test(navigator.userAgent) && /Google Inc/.test(navigator.vendor));
    console.log('- 是否HTTPS:', location.protocol === 'https:' || location.hostname === 'localhost');
    console.log('- 在线状态:', navigator.onLine);
}

// 检查权限状态
async function checkPermissions() {
    console.log('🔐 权限检查:');
    try {
        if (navigator.permissions && navigator.permissions.query) {
            const permission = await navigator.permissions.query({ name: 'geolocation' });
            console.log('- 权限状态:', permission.state);
            return permission.state;
        } else {
            console.log('- 无法检查权限状态（浏览器不支持）');
            return 'unknown';
        }
    } catch (error) {
        console.log('- 权限检查失败:', error.message);
        return 'error';
    }
}

// 测试地理位置获取
function testGeolocation() {
    console.log('🌍 地理位置测试:');
    
    if (!navigator.geolocation) {
        console.log('❌ 浏览器不支持地理位置功能');
        return;
    }
    
    const options = {
        enableHighAccuracy: false,
        timeout: 15000,
        maximumAge: 300000
    };
    
    console.log('- 开始获取位置...');
    const startTime = Date.now();
    
    navigator.geolocation.getCurrentPosition(
        function(position) {
            const endTime = Date.now();
            const duration = endTime - startTime;
            
            console.log('✅ 地理位置获取成功!');
            console.log('- 耗时:', duration + 'ms');
            console.log('- 纬度:', position.coords.latitude);
            console.log('- 经度:', position.coords.longitude);
            console.log('- 精度:', position.coords.accuracy + ' 米');
            console.log('- 时间戳:', new Date(position.timestamp).toLocaleString());
        },
        function(error) {
            const endTime = Date.now();
            const duration = endTime - startTime;
            
            console.log('❌ 地理位置获取失败!');
            console.log('- 耗时:', duration + 'ms');
            console.log('- 错误代码:', error.code);
            
            let errorMessage = '';
            switch (error.code) {
                case error.PERMISSION_DENIED:
                    errorMessage = '位置访问被拒绝';
                    break;
                case error.POSITION_UNAVAILABLE:
                    errorMessage = '位置信息不可用';
                    break;
                case error.TIMEOUT:
                    errorMessage = '位置请求超时';
                    break;
                default:
                    errorMessage = '未知错误';
            }
            
            console.log('- 错误信息:', errorMessage);
            console.log('- 详细错误:', error.message);
            
            // 提供修复建议
            provideFixSuggestions(error.code);
        },
        options
    );
}

// 提供修复建议
function provideFixSuggestions(errorCode) {
    console.log('💡 修复建议:');
    
    switch (errorCode) {
        case 1: // PERMISSION_DENIED
            console.log('1. 点击地址栏左侧的锁定图标 🔒');
            console.log('2. 将"位置"设置为"允许"');
            console.log('3. 刷新页面后重试');
            console.log('4. 如果问题持续，检查Chrome设置 → 隐私设置和安全性 → 网站设置 → 位置信息');
            break;
        case 2: // POSITION_UNAVAILABLE
            console.log('1. 检查设备的位置服务是否开启');
            console.log('2. 确保GPS已开启（移动设备）');
            console.log('3. 尝试在室外或靠近窗户的地方使用');
            console.log('4. 检查网络连接');
            break;
        case 3: // TIMEOUT
            console.log('1. 检查网络连接');
            console.log('2. 尝试在室外使用');
            console.log('3. 等待几秒钟后重试');
            console.log('4. 重启设备的位置服务');
            break;
        default:
            console.log('1. 刷新页面重试');
            console.log('2. 清除浏览器缓存');
            console.log('3. 重启Chrome浏览器');
    }
}

// 运行完整测试
async function runFullTest() {
    console.log('🚀 开始完整测试...\n');
    
    // 步骤1: 环境检查
    checkEnvironment();
    console.log('');
    
    // 步骤2: 权限检查
    await checkPermissions();
    console.log('');
    
    // 步骤3: 地理位置测试
    testGeolocation();
}

// 导出函数供外部调用
window.geolocationTest = {
    checkEnvironment,
    checkPermissions,
    testGeolocation,
    runFullTest
};

console.log('📝 测试脚本已加载。运行 geolocationTest.runFullTest() 开始测试。'); 