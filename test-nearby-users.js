// 附近用户查找功能测试脚本
// 在浏览器控制台中运行此脚本来测试功能

console.log('🔍 附近用户查找功能测试开始...');

// 测试查找附近用户功能
async function testFindNearbyUsers() {
    console.log('📋 测试步骤:');
    console.log('1. 检查用户是否已分享位置');
    console.log('2. 调用查找附近用户API');
    console.log('3. 验证返回结果');
    
    try {
        // 步骤1: 检查用户位置
        console.log('\n🔍 步骤1: 检查用户位置...');
        
        // 获取当前用户位置（从页面数据中）
        const currentUserLocation = window.currentUser?.location;
        if (!currentUserLocation) {
            console.log('❌ 用户未分享位置，请先分享位置');
            return;
        }
        
        console.log('✅ 用户位置:', currentUserLocation);
        
        // 步骤2: 调用API
        console.log('\n🌍 步骤2: 调用查找附近用户API...');
        
        const response = await fetch('/api/where-is-my-friends/locations/nearby', {
            method: 'GET',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
            },
            body: JSON.stringify({
                latitude: currentUserLocation.latitude,
                longitude: currentUserLocation.longitude,
                distance: 50
            })
        });
        
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        
        const result = await response.json();
        console.log('✅ API响应:', result);
        
        // 步骤3: 验证结果
        console.log('\n📊 步骤3: 验证结果...');
        
        if (result.users && Array.isArray(result.users)) {
            console.log(`✅ 找到 ${result.users.length} 个用户`);
            
            result.users.forEach((user, index) => {
                console.log(`${index + 1}. ${user.username} - ${user.distance}km away`);
                if (user.isCurrentUser) {
                    console.log('   👤 这是当前用户');
                }
            });
            
            // 检查是否包含当前用户
            const hasCurrentUser = result.users.some(user => user.isCurrentUser);
            if (hasCurrentUser) {
                console.log('✅ 结果包含当前用户');
            } else {
                console.log('⚠️ 结果不包含当前用户');
            }
            
        } else {
            console.log('❌ 返回的用户数据格式不正确');
        }
        
    } catch (error) {
        console.error('❌ 测试失败:', error);
    }
}

// 测试按钮点击功能
function testButtonClick() {
    console.log('🔘 测试按钮点击功能...');
    
    // 查找按钮
    const findButton = document.querySelector('button[data-action="findNearbyUsers"]') || 
                      document.querySelector('button:contains("查看附近的朋友")');
    
    if (findButton) {
        console.log('✅ 找到查找按钮');
        console.log('点击按钮...');
        findButton.click();
        
        // 检查按钮状态
        setTimeout(() => {
            if (findButton.disabled) {
                console.log('✅ 按钮被禁用（正在加载）');
            } else {
                console.log('⚠️ 按钮未被禁用');
            }
        }, 100);
        
    } else {
        console.log('❌ 未找到查找按钮');
    }
}

// 检查页面状态
function checkPageState() {
    console.log('📄 检查页面状态...');
    
    // 检查用户位置状态
    const hasLocation = !!window.currentUser?.location;
    console.log('用户已分享位置:', hasLocation);
    
    // 检查按钮状态
    const buttons = document.querySelectorAll('button');
    console.log('页面按钮数量:', buttons.length);
    
    buttons.forEach((button, index) => {
        const text = button.textContent.trim();
        if (text.includes('查看') || text.includes('查找') || text.includes('nearby')) {
            console.log(`按钮 ${index + 1}: "${text}" - 禁用状态: ${button.disabled}`);
        }
    });
    
    // 检查错误信息
    const errors = document.querySelectorAll('.alert-error');
    if (errors.length > 0) {
        console.log('⚠️ 发现错误信息:', errors.length, '个');
        errors.forEach((error, index) => {
            console.log(`错误 ${index + 1}:`, error.textContent.trim());
        });
    }
    
    // 检查用户列表
    const userList = document.querySelector('.users-list');
    if (userList) {
        const userCards = userList.querySelectorAll('.user-card');
        console.log('用户卡片数量:', userCards.length);
    } else {
        console.log('未找到用户列表');
    }
}

// 运行完整测试
async function runFullTest() {
    console.log('🚀 开始完整测试...\n');
    
    // 检查页面状态
    checkPageState();
    
    // 测试按钮点击
    testButtonClick();
    
    // 测试API调用
    await testFindNearbyUsers();
    
    console.log('\n✅ 测试完成！');
}

// 导出函数供外部调用
window.nearbyUsersTest = {
    testFindNearbyUsers,
    testButtonClick,
    checkPageState,
    runFullTest
};

console.log('📝 测试脚本已加载。运行 nearbyUsersTest.runFullTest() 开始测试。');

// 自动运行基础检查
setTimeout(() => {
    console.log('\n🔍 自动运行基础检查...');
    checkPageState();
}, 1000); 